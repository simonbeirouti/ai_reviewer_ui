defmodule AiReviewerWeb.RepoTesterLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.Accounts
  alias AiReviewer.GithubService
  alias Phoenix.LiveView.JS

  def mount(%{"repo_name" => repo_name}, session, socket) do
    current_user = if session["user_id"] do
      Accounts.get_user!(session["user_id"])
    end

    repo_data = case current_user do
      %{github_token: token, name: username} ->
        case GithubService.get_repository(username, repo_name, token) do
          {:ok, data} -> data
          _ -> nil
        end
      _ -> nil
    end

    # Get repository contents for file tree
    repo_contents = case current_user do
      %{github_token: token, name: username} ->
        case fetch_directory_contents(username, repo_name, token, "") do
          {:ok, contents} -> build_file_tree(contents)
          _ -> %{}
        end
      _ -> %{}
    end

    {:ok, assign(socket,
      repo: repo_data,
      current_user: current_user,
      repo_contents: repo_contents,
      selected_file: nil,
      original_content: nil,
      generated_tests: nil,
      is_generating: false,
      show_loading_modal: false,
      error: if(is_nil(repo_data), do: "Repository not found", else: nil),
      page_title: "AI Test Writer - #{repo_name}",
      current_path: "/dashboard/repo/#{repo_name}/tester",
      file_changes: %{},
      is_loading: false,
      expanded_folders: MapSet.new(),
      test_file_path: nil
    )}
  end

  # Recursively fetch directory contents
  defp fetch_directory_contents(username, repo, token, path) do
    case GithubService.get_repository_contents(username, repo, token, path) do
      {:ok, contents} when is_list(contents) ->
        # Process each item in the directory
        processed_contents = Enum.map(contents, fn item ->
          if item["type"] == "dir" do
            # If it's a directory, recursively fetch its contents
            case fetch_directory_contents(username, repo, token, item["path"]) do
              {:ok, sub_contents} ->
                Map.put(item, "contents", sub_contents)
              _ ->
                Map.put(item, "contents", [])
            end
          else
            # If it's a file, return as is
            item
          end
        end)
        {:ok, processed_contents}
      {:ok, single_item} when is_map(single_item) ->
        # Handle case where response is a single item
        {:ok, [single_item]}
      error ->
        error
    end
  end

  # Helper function to build file tree structure
  defp build_file_tree(contents) do
    contents
    |> Enum.reduce(%{}, fn item, acc ->
      path_parts = String.split(item["path"], "/")
      insert_into_tree(acc, path_parts, item)
    end)
  end

  defp insert_into_tree(tree, [part], item) do
    Map.put(tree, part, item)
  end

  defp insert_into_tree(tree, [head | tail], item) do
    subtree = Map.get(tree, head, %{})
    Map.put(tree, head, insert_into_tree(subtree, tail, item))
  end

  def handle_event("select_file", %{"path" => path}, socket) do
    socket = assign(socket, is_loading: true)

    case socket.assigns.current_user do
      %{github_token: token, name: username} ->
        case GithubService.get_file_content(
          username,
          socket.assigns.repo["name"],
          path,
          "main",
          token
        ) do
          {:ok, content} ->
            {:noreply, assign(socket,
              selected_file: path,
              original_content: content,
              ai_suggestions: nil,
              is_loading: false
            )}
          {:error, reason} ->
            {:noreply, socket
              |> assign(is_loading: false)
              |> put_flash(:error, "Failed to load file: #{reason}")
            }
        end
      _ ->
        {:noreply, socket
          |> assign(is_loading: false)
          |> put_flash(:error, "User not authenticated")
        }
    end
  end

  def handle_event("generate_tests", _params, socket) do
    case socket.assigns.selected_file do
      nil ->
        {:noreply, put_flash(socket, :error, "Please select a file first")}
      file_path ->
        # First update the UI to show loading state
        socket = assign(socket, is_generating: true, show_loading_modal: true)

        # Start the async task
        Process.send_after(self(), :generate_tests, 0)

        {:noreply, socket}
    end
  end

  # Handle the async test generation
  def handle_info(:generate_tests, socket) do
    test_file_path = generate_test_file_path(socket.assigns.selected_file)

    case AiReviewer.AiService.generate_tests(socket.assigns.original_content, socket.assigns.selected_file) do
      {:ok, tests} ->
        {:noreply, assign(socket,
          is_generating: false,
          show_loading_modal: false,
          generated_tests: tests,
          test_file_path: test_file_path
        )}
      {:error, reason} ->
        {:noreply, socket
          |> assign(is_generating: false, show_loading_modal: false)
          |> put_flash(:error, "Failed to generate tests: #{reason}")}
    end
  end

  def handle_event("commit_tests", _params, %{assigns: %{test_file_path: path, generated_tests: tests}} = socket) do
    case create_and_commit_test_file(
      socket.assigns.current_user,
      socket.assigns.repo["name"],
      path,
      tests
    ) do
      {:ok, _} ->
        {:noreply, socket
          |> assign(generated_tests: nil, test_file_path: nil)
          |> put_flash(:info, "Tests committed successfully!")}
      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to commit tests: #{reason}")}
    end
  end

  # Helper function to generate test file path
  defp generate_test_file_path(file_path) do
    # Handle different file path patterns
    cond do
      # If it's already a test file, keep it in the test directory
      String.contains?(file_path, "/test/") ->
        file_path

      # If it's in lib directory, convert lib/foo/bar.ex to test/foo/bar_test.exs
      String.starts_with?(file_path, "lib/") ->
        file_path
        |> String.replace_prefix("lib/", "test/")
        |> String.replace_suffix(".ex", "_test.exs")

      # For root directory files or any other files
      true ->
        filename = Path.basename(file_path)
        base_name = Path.rootname(filename)
        Path.join("test", "#{base_name}_test.exs")
    end
  end

  # Helper function to extract module name from content
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([^\s]+)\s+do/, content) do
      [_, module_name] -> module_name
      _ -> "UnknownModule"
    end
  end

  # Helper function to create and commit test file
  defp create_and_commit_test_file(user, repo_name, test_file_path, content) do
    # Add logging to verify the path
    IO.puts("Creating/updating test file at path: #{test_file_path}")

    case user do
      %{github_token: token, name: username} ->
        # Ensure test directory exists first
        test_dir = Path.dirname(test_file_path)

        # Try to create test directory if it doesn't exist
        if test_dir != "." do
          GithubService.create_file(
            username,
            repo_name,
            "#{test_dir}/.keep",
            %{
              message: "Ensure test directory exists",
              content: Base.encode64("")
            },
            token
          )
        end

        # Now create/update the test file
        case GithubService.get_repository_contents(username, repo_name, token, test_file_path) do
          {:ok, file_data} when is_map(file_data) ->
            # File exists, update it
            GithubService.update_file(
              username,
              repo_name,
              test_file_path,
              %{
                message: "Update generated tests for #{test_file_path}",
                content: Base.encode64(content),
                sha: file_data["sha"]
              },
              token
            )
          _ ->
            # File doesn't exist, create it
            GithubService.create_file(
              username,
              repo_name,
              test_file_path,
              %{
                message: "Add generated tests for #{test_file_path}",
                content: Base.encode64(content)
              },
              token
            )
        end
      _ ->
        {:error, "User not authenticated"}
    end
  end

  def handle_event("toggle_folder", %{"path" => path}, socket) do
    expanded_folders = socket.assigns.expanded_folders
    new_expanded_folders = if MapSet.member?(expanded_folders, path) do
      MapSet.delete(expanded_folders, path)
    else
      MapSet.put(expanded_folders, path)
    end

    {:noreply, assign(socket, expanded_folders: new_expanded_folders)}
  end

  def render_file_tree(assigns) do
    ~H"""
    <div class="space-y-1">
      <%= for {name, item} <- @tree do %>
        <%= if is_map(item) && (item["type"] == "dir" || !Map.has_key?(item, "type")) do %>
          <div class="file-tree-item">
            <button
              phx-click="toggle_folder"
              phx-value-path={item["path"] || name}
              class="w-full flex items-center px-2 py-1 text-sm text-gray-600 hover:bg-gray-100 rounded"
            >
              <div class="flex items-center flex-1">
                <%= if MapSet.member?(@expanded_folders, item["path"] || name) do %>
                  <svg class="h-4 w-4 mr-1 text-gray-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                <% else %>
                  <svg class="h-4 w-4 mr-1 text-gray-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                  </svg>
                <% end %>
                <svg class="h-4 w-4 mr-2 text-gray-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
                </svg>
                <span class="font-medium truncate"><%= name %></span>
              </div>
            </button>
            <%= if MapSet.member?(@expanded_folders, item["path"] || name) do %>
              <div class="pl-6">
                <%= if item["contents"] do %>
                  <.render_file_tree tree={Enum.reduce(item["contents"], %{}, fn content, acc ->
                    Map.put(acc, content["name"], content)
                  end)} expanded_folders={@expanded_folders} selected_file={@selected_file} />
                <% else %>
                  <.render_file_tree tree={item} expanded_folders={@expanded_folders} selected_file={@selected_file} />
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="file-tree-item">
            <button
              phx-click="select_file"
              phx-value-path={item["path"]}
              class={"w-full flex items-center px-2 py-1 text-sm hover:bg-gray-100 rounded #{if @selected_file == item["path"], do: "bg-blue-50 text-blue-600", else: "text-gray-600"}"}
            >
              <div class="flex items-center flex-1">
                <svg class="h-4 w-4 mr-2 text-gray-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <span class="truncate"><%= name %></span>
              </div>
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100">
      <!-- Loading Modal -->
      <%= if @show_loading_modal do %>
        <div class="fixed z-50 inset-0 overflow-y-auto" phx-window-keydown="close_modal" phx-key="escape">
          <div class="fixed inset-0 flex items-center justify-center">
            <!-- Background overlay -->
            <div class="absolute inset-0 bg-gray-500 bg-opacity-75 transition-opacity"></div>

            <!-- Modal panel -->
            <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
              <div class="bg-white p-8 rounded-lg shadow-lg flex flex-col items-center">
                <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mb-4"></div>
                <p class="text-lg font-semibold">AI is creating comprehensive test cases....</p>
                <p class="text-sm text-gray-500 mt-2">This may take a few moments</p>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Header -->
      <div class="bg-white shadow border-b border-gray-200">
        <div class="px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex justify-between items-center">
            <div class="flex items-center">
              <a href={~p"/dashboard/repos"} class="text-gray-500 hover:text-gray-700">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
                </svg>
              </a>
              <h1 class="ml-4 text-2xl font-bold text-gray-900">AI Test Writer</h1>
            </div>
            <div class="flex items-center">
              <span class="text-gray-600"><%= @current_user.name %></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div>
        <div class="grid grid-cols-12 h-screen">
          <!-- Left Sidebar: File Tree -->
          <div class="col-span-2 bg-white overflow-hidden border-r border-gray-200 h-full">
            <div class="p-4 border-b border-gray-200">
              <h2 class="text-lg font-semibold text-gray-900">Files</h2>
            </div>
            <div class="p-4 overflow-auto max-h-[calc(100vh-16rem)]">
              <.render_file_tree
                tree={@repo_contents}
                expanded_folders={@expanded_folders}
                selected_file={@selected_file}
              />
            </div>
              </div>

          <!-- Middle: Original Code -->
          <div class="col-span-5 bg-white overflow-hidden border-r border-gray-200 h-full">
            <div class="p-4 border-b border-gray-200 flex justify-between items-center">
              <h2 class="text-lg font-semibold text-gray-900">Code</h2>
              <%= if @selected_file do %>
                <p class="text-sm text-gray-500 mt-1"><%= @selected_file %></p>
              <% end %>
            </div>
            <div class="relative h-full">
              <%= if @is_loading do %>
                <div class="absolute inset-0 bg-white bg-opacity-75 flex items-center justify-center">
                  <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
                </div>
              <% end %>
              <div class="p-4 overflow-auto max-h-[calc(100vh-4rem)]">
                <%= if @original_content do %>
                  <pre class="h-full text-sm font-mono bg-gray-50 p-4 rounded-md overflow-auto"><code><%= @original_content %></code></pre>
                <% else %>
                  <div class="text-center py-8 text-gray-500">
                    <svg xmlns="http://www.w3.org/2000/svg" class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                    <p class="mt-2">Select a file to view its content</p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Right: Generated Tests -->
          <div class="col-span-5 bg-white overflow-hidden h-full">
            <div class="px-4 py-2.5 border-b border-gray-200 flex justify-between items-center">
              <div>
              <h2 class="text-lg font-semibold text-gray-900">Generated Tests</h2>
                <%= if @test_file_path do %>
                  <p class="text-sm text-gray-500"><%= @test_file_path %></p>
                <% end %>
              </div>
              <div class="flex space-x-2">
              <button
                phx-click="generate_tests"
                  phx-disable-with="Analyzing..."
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
                disabled={is_nil(@selected_file) || @is_generating}
              >
                <%= if @is_generating do %>
                  <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                    Analyzing Code...
                <% else %>
                  Generate Tests
                <% end %>
              </button>
                <%= if @generated_tests do %>
                  <button
                    phx-click="commit_tests"
                    class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                  >
                    Commit Tests
                  </button>
                <% end %>
              </div>
            </div>
            <div class="p-4 overflow-auto max-h-[calc(100vh-4rem)]">
              <%= if @is_generating do %>
                <div class="flex flex-col items-center justify-center py-12 space-y-4">
                  <div class="animate-pulse flex space-x-4">
                    <div class="h-12 w-12">
                      <svg class="animate-spin text-blue-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                    </div>
                  </div>
                  <div class="text-center">
                    <h3 class="text-lg font-medium text-gray-900">Generating Tests</h3>
                    <p class="mt-1 text-sm text-gray-500">
                      AI is analyzing your code and creating comprehensive test cases...
                    </p>
                  </div>
                </div>
              <% else %>
                <%= if @generated_tests do %>
                  <div class="space-y-4">
                    <pre class="text-sm font-mono bg-gray-50 p-4 rounded-md overflow-auto"><code><%= @generated_tests %></code></pre>
                  </div>
                <% else %>
                  <div class="text-center py-8 text-gray-500">
                    <svg xmlns="http://www.w3.org/2000/svg" class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                    </svg>
                    <p class="mt-2">Select a file and click "Generate Tests" to create test cases</p>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
