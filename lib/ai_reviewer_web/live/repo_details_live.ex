defmodule AiReviewerWeb.RepoDetailsLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.GithubService
  alias AiReviewer.Accounts
  alias Phoenix.LiveView.JS
  import AiReviewerWeb.CoreComponents

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

    branches = case current_user do
      %{github_token: token, name: username} ->
        case GithubService.get_branches(username, repo_name, token) do
          {:ok, data} -> data
          _ -> []
        end
      _ -> []
    end

    pull_requests = case current_user do
      %{github_token: token, name: username} ->
        case GithubService.get_pull_requests(username, repo_name, token, "open") do
          {:ok, data} -> data
          _ -> []
        end
      _ -> []
    end

    {:ok, socket = assign(socket,
      repo: repo_data,
      branches: branches,
      pull_requests: pull_requests,
      selected_branch: List.first(branches)["name"],
      selected_pr: nil,
      selected_pr_data: nil,
      pr_comments: [],
      pr_files: [],
      base_file_contents: %{},
      head_file_contents: %{},
      selected_file: nil,
      selected_line: nil,
      editing_line: nil,
      edited_content: "",
      edit_suggestions: %{},
      anti_pattern_suggestions: [],
      pr_status: "open",
      error: if(is_nil(repo_data), do: "Repository not found", else: nil),
      current_user: current_user,
      current_path: "/dashboard/repo/#{repo_name}",
      is_loading_files: false,
      debug_info: "Initialized and ready",
      file_changes: %{}
    )}
  end

  def handle_event("select_branch", %{"branch" => branch_name}, socket) do
    {:noreply, assign(socket, selected_branch: branch_name)}
  end

  def handle_event("select_pr_status", %{"status" => status}, socket) do
    fetch_pull_requests_by_status(status, socket)
  end

  def handle_event("select_pr_status", %{"value" => %{"status" => status}}, socket) do
    fetch_pull_requests_by_status(status, socket)
  end

  def handle_event("select_pr_status", params, socket) do
    status = params["status"] || params["value"]["status"] || params["value-status"]
    if status do
      fetch_pull_requests_by_status(status, socket)
    else
      IO.inspect(params, label: "Invalid PR status params")
      {:noreply, socket}
    end
  end

  def handle_event("select_pr", %{"pr" => pr_number}, socket) do
    fetch_pull_request_data(pr_number, socket)
  end

  def handle_event("select_pr", %{"value" => %{"pr" => pr_number}}, socket) do
    fetch_pull_request_data(pr_number, socket)
  end

  def handle_event("force_refresh", %{"filename" => filename}, socket) do

    if socket.assigns.selected_pr_data && socket.assigns.current_user do
      %{github_token: token, name: username} = socket.assigns.current_user
      pr_data = socket.assigns.selected_pr_data


      # Directly fetch the file synchronously for debugging
      case GithubService.get_file_content(
        username,
        socket.assigns.repo["name"],
        filename,
        pr_data["head"]["sha"],
        token
      ) do
        {:ok, content} ->

          head_file_contents = Map.put(socket.assigns.head_file_contents, filename, content)

          {:noreply, assign(socket,
            head_file_contents: head_file_contents,
            is_loading_files: false,
            debug_info: "File loaded directly: #{byte_size(content)} bytes, type: #{typeof(content)}"
          )}
        {:error, reason} ->

          {:noreply, assign(socket,
            is_loading_files: false,
            debug_info: "Error: #{reason}"
          )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({ref, _message}, socket) when is_reference(ref) do
    # Task completed, we don't need to do anything with the reference
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    # Task process went down, we can ignore this
    {:noreply, socket}
  end

  def handle_info({:base_file_loaded, filename, content}, socket) do
    IO.inspect({filename, byte_size(content), String.slice(content, 0..50)}, label: "Base file loaded with preview")
    base_file_contents = Map.put(socket.assigns.base_file_contents, filename, content)

    # Check if we've loaded all files
    is_loading = check_all_files_loaded(socket.assigns.pr_files, base_file_contents, socket.assigns.head_file_contents)
    IO.inspect(is_loading, label: "Still loading files?")

    socket = socket
      |> assign(base_file_contents: base_file_contents)
      |> assign(is_loading_files: is_loading)
      |> assign(debug_info: "Base file loaded: #{filename}, #{byte_size(content)} bytes")

    {:noreply, socket}
  end

  def handle_info({:head_file_loaded, filename, content}, socket) do
    head_file_contents = Map.put(socket.assigns.head_file_contents, filename, content)

    # Check if we've loaded all files
    is_loading = check_all_files_loaded(socket.assigns.pr_files, socket.assigns.base_file_contents, head_file_contents)

    socket = socket
      |> assign(head_file_contents: head_file_contents)
      |> assign(is_loading_files: is_loading)
      |> assign(debug_info: "Head file loaded: #{filename}, #{byte_size(content || "")} bytes, type: #{typeof(content)}")

    {:noreply, socket}
  end

  def handle_info({:file_load_error, filename, error}, socket) do
    IO.inspect(error, label: "Error loading file: #{filename}")

    # Even if there's an error, update loading status
    is_loading = check_all_files_loaded(socket.assigns.pr_files, socket.assigns.base_file_contents, socket.assigns.head_file_contents)

    {:noreply, assign(socket, is_loading_files: is_loading)}
  end

  # Check if all files from the PR have been loaded
  defp check_all_files_loaded(pr_files, base_contents, head_contents) do
    if length(pr_files) == 0 do
      false
    else
      # Check if we have at least the selected file loaded
      missing_files = Enum.filter(pr_files, fn file ->
        filename = file["filename"]
        !Map.has_key?(head_contents, filename)
      end)

      IO.inspect(length(missing_files), label: "Number of missing files")
      length(missing_files) > 0
    end
  end

  defp fetch_base_file(username, repo, filename, sha, token) do
    IO.inspect({username, repo, filename, sha}, label: "Base file details")
    case GithubService.get_file_content(username, repo, filename, sha, token) do
      {:ok, content} ->
        IO.inspect({:ok, filename, byte_size(content)}, label: "Base file fetch result")
        send(self(), {:base_file_loaded, filename, content})
      {:error, reason} ->
        IO.inspect({:error, filename, reason}, label: "Base file fetch error")
        send(self(), {:file_load_error, filename, reason})
    end
  end

  defp fetch_head_file(username, repo, filename, sha, token) do
    IO.inspect({username, repo, filename, sha}, label: "Head file details")
    case GithubService.get_file_content(username, repo, filename, sha, token) do
      {:ok, content} ->
        IO.inspect({:ok, filename, byte_size(content)}, label: "Head file fetch result")
        send(self(), {:head_file_loaded, filename, content})
      {:error, reason} ->
        IO.inspect({:error, filename, reason}, label: "Head file fetch error")
        send(self(), {:file_load_error, filename, reason})
    end
  end

  defp fetch_pull_requests_by_status(status, socket) do
    IO.inspect(status, label: "Selected PR status")
    IO.inspect(socket.assigns, label: "Current socket assigns")

    socket = assign(socket, pr_status: status)

    case socket.assigns.current_user do
      %{github_token: token, name: username} = user ->
        IO.inspect(user, label: "Current user")
        IO.inspect(socket.assigns.repo["name"], label: "Repo name")

        case GithubService.get_pull_requests(username, socket.assigns.repo["name"], token, status) do
          {:ok, prs} ->
            IO.inspect(length(prs), label: "Number of PRs received")
            IO.inspect(prs, label: "PRs data")
            {:noreply, assign(socket, pull_requests: prs)}
          error ->
            IO.inspect(error, label: "Error fetching PRs")
            {:noreply, assign(socket, pull_requests: [])}
        end
      _ ->
        IO.inspect("No current user found", label: "Error")
        {:noreply, assign(socket, pull_requests: [])}
    end
  end

  defp fetch_pull_request_data(pr_number, socket) do
    case socket.assigns.current_user do
      %{github_token: token, name: username} ->
        with {:ok, review_comments} <- GithubService.get_pull_request_comments(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, issue_comments} <- GithubService.get_pull_request_issue_comments(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, pr_data} <- GithubService.get_pull_request_diff(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, files} <- GithubService.get_pull_request_files(username, socket.assigns.repo["name"], pr_number, token) do

          # Combine both types of comments
          all_comments = issue_comments ++ review_comments

          # Select the first file by default if there are any files
          first_file = if length(files) > 0, do: List.first(files)["filename"], else: nil

          socket = assign(socket,
            selected_pr: pr_number,
            pr_comments: all_comments,
            selected_pr_data: pr_data,
            pr_files: files,
            base_file_contents: %{},
            head_file_contents: %{},
            selected_file: first_file,
            is_loading_files: length(files) > 0,
            debug_info: "PR #{pr_number} loaded with #{length(files)} files"
          )

          # If there are files, load them directly
          if first_file do
            # Immediately load the first file synchronously to ensure it's available
            case load_file_synchronously(username, socket.assigns.repo["name"], first_file, pr_data["head"]["sha"], token) do
              {:ok, content} ->
                head_file_contents = Map.put(socket.assigns.head_file_contents, first_file, content)

                socket = socket
                  |> assign(head_file_contents: head_file_contents)
                  |> assign(is_loading_files: false)
                  |> assign(debug_info: "PR #{pr_number} loaded with #{length(files)} files. First file loaded: #{byte_size(content)} bytes")

                # Then start loading other files asynchronously
                load_remaining_files_async(socket, files, first_file)

                {:noreply, socket}

              {:error, reason} ->
                socket = assign(socket, debug_info: "Error loading first file: #{inspect(reason)}")

                # Still start loading other files asynchronously
                load_remaining_files_async(socket, files, first_file)

                {:noreply, socket}
            end
          else
            {:noreply, socket}
          end
        else
          error ->
            IO.inspect(error, label: "Error in PR selection")
            {:noreply, assign(socket,
              selected_pr: pr_number,
              pr_comments: [],
              selected_pr_data: nil,
              pr_files: [],
              base_file_contents: %{},
              head_file_contents: %{},
              selected_file: nil,
              is_loading_files: false,
              debug_info: "Error loading PR: #{inspect(error)}",
              repo: socket.assigns.repo
            )}
        end
      _ ->
        {:noreply, assign(socket,
          selected_pr: pr_number,
          pr_comments: [],
          selected_pr_data: nil,
          pr_files: [],
          base_file_contents: %{},
          head_file_contents: %{},
          selected_file: nil,
          is_loading_files: false,
          debug_info: "No user credentials available",
          repo: socket.assigns.repo
        )}
    end
  end

  # Load a file synchronously for immediate display
  defp load_file_synchronously(username, repo, filename, sha, token) do
    GithubService.get_file_content(username, repo, filename, sha, token)
  end

  # Load remaining files asynchronously in the background
  defp load_remaining_files_async(socket, files, skip_file) do
    %{github_token: token, name: username} = socket.assigns.current_user
    pr_data = socket.assigns.selected_pr_data

    # Filter out the already loaded first file
    remaining_files = Enum.filter(files, fn file ->
      file["filename"] != skip_file
    end)

    Enum.each(remaining_files, fn file ->
      filename = file["filename"]

      # Base file (from base branch)
      spawn(fn ->
        fetch_base_file(username, socket.assigns.repo["name"], filename, pr_data["base"]["sha"], token)
      end)

      # Head file (from head branch)
      spawn(fn ->
        fetch_head_file(username, socket.assigns.repo["name"], filename, pr_data["head"]["sha"], token)
      end)
    end)
  end

  def render(assigns) do
    # Format code with line numbers if there's a selected file with content
    formatted_code = if assigns.selected_file && Map.has_key?(assigns.head_file_contents, assigns.selected_file) do
      content = Map.get(assigns.head_file_contents, assigns.selected_file, "")
      format_code_with_line_numbers(content)
    else
      %{lines: [], count: 0}
    end

    # Add the formatted code to assigns for use in the template
    assigns = assign(assigns, :formatted_code, formatted_code)

    ~H"""
    <div id="main-container" class="h-[calc(100vh-4rem)] flex flex-col">
      <!-- Top navigation bar -->
      <div class="bg-gray-100 p-4 border-b border-gray-200">
        <div class="flex flex-wrap justify-between items-center gap-4">
          <div class="flex flex-row items-center gap-4 justify-start">
            <a href={~p"/dashboard/repos"} class="text-blue-500 hover:underline flex items-center justify-start">
              <.icon name="hero-arrow-left-solid" class="h-3 w-3 mr-1" />
              <span>Back to repositories</span>
            </a>
          </div>

          <div class="flex flex-row items-center gap-4 justify-end">
            <div class="relative dropdown-container">
              <button
                type="button"
                class="px-4 py-2 bg-white border border-gray-300 rounded-md shadow-sm flex items-center gap-2 hover:bg-gray-50"
                onclick="event.stopPropagation(); document.querySelectorAll('[id$=-dropdown]').forEach(d => d.style.display = 'none'); const dropdown = document.getElementById('pr-status-dropdown'); dropdown.style.display = dropdown.style.display === 'none' ? 'block' : 'none';"
                aria-expanded="false"
              >
                <span>PR Status: <%= String.capitalize(@pr_status) %></span>
                <.icon name="hero-chevron-down-solid" class="h-4 w-4" />
              </button>
              <div id="pr-status-dropdown" class="absolute right-0 mt-2 w-48 bg-white border border-gray-200 rounded-md shadow-lg z-10 hidden" style="display: none;">
                <div class="py-1">
                  <button
                    type="button"
                    phx-click="select_pr_status"
                    phx-value-status="open"
                    class={"block w-full text-left px-4 py-2 text-sm hover:bg-gray-100 #{@pr_status == "open" && "bg-blue-50 text-blue-600"}"}
                    onclick="document.getElementById('pr-status-dropdown').style.display = 'none';"
                  >
                    Open
                  </button>
                  <button
                    type="button"
                    phx-click="select_pr_status"
                    phx-value-status="closed"
                    class={"block w-full text-left px-4 py-2 text-sm hover:bg-gray-100 #{@pr_status == "closed" && "bg-blue-50 text-blue-600"}"}
                    onclick="document.getElementById('pr-status-dropdown').style.display = 'none';"
                  >
                    Closed
                  </button>
                  <button
                    type="button"
                    phx-click="select_pr_status"
                    phx-value-status="all"
                    class={"block w-full text-left px-4 py-2 text-sm hover:bg-gray-100 #{@pr_status == "all" && "bg-blue-50 text-blue-600"}"}
                    onclick="document.getElementById('pr-status-dropdown').style.display = 'none';"
                  >
                    All
                  </button>
                </div>
              </div>
            </div>

            <div class="relative dropdown-container">
              <button
                type="button"
                class="px-4 py-2 bg-white border border-gray-300 rounded-md shadow-sm flex items-center gap-2 hover:bg-gray-50"
                onclick="event.stopPropagation(); document.querySelectorAll('[id$=-dropdown]').forEach(d => d.style.display = 'none'); const dropdown = document.getElementById('pr-list-dropdown'); dropdown.style.display = dropdown.style.display === 'none' ? 'block' : 'none';"
                aria-expanded="false"
              >
                <span>Pull Requests <%= if @selected_pr, do: "(##{@selected_pr})" %></span>
                <.icon name="hero-chevron-down-solid" class="h-4 w-4" />
              </button>
              <div id="pr-list-dropdown" class="absolute right-0 mt-2 w-64 max-h-96 overflow-y-auto bg-white border border-gray-200 rounded-md shadow-lg z-10 hidden" style="display: none;">
                <div class="py-1">
                  <%= if length(@pull_requests) == 0 do %>
                    <div class="text-gray-500 text-center py-4">
                      No pull requests found for status: <%= @pr_status %>
                    </div>
                  <% else %>
                    <%= for pr <- @pull_requests do %>
                      <button
                        type="button"
                        phx-click="select_pr"
                        phx-value-pr={pr["number"]}
                        class={"block w-full text-left px-4 py-2 hover:bg-gray-100 #{pr["number"] == @selected_pr && "bg-blue-50"}"}
                        onclick="document.getElementById('pr-list-dropdown').style.display = 'none';"
                      >
                        <div class="font-medium">#<%= pr["number"] %> <%= pr["title"] %></div>
                        <div class="text-sm text-gray-600">
                          <p><%= pr["user"]["login"] %> • <%= format_date(pr["created_at"]) %></p>
                          <p class={"text-sm font-medium #{if pr["state"] == "open", do: "text-green-600", else: "text-red-600"}"}>
                            <%= String.capitalize(pr["state"]) %>
                          </p>
                        </div>
                      </button>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex-1 p-4 overflow-y-auto">
        <%= if @error do %>
          <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
            <%= @error %>
          </div>
        <% end %>

        <%= if @selected_pr_data do %>
          <div class="bg-white">
            <div class="flex flex-row items-center justify-between gap-4 mb-4">
              <div class="flex flex-row gap-2">
                <h3 class="text-xl font-medium text-gray-900">#<%= @selected_pr_data["number"] %> <%= @selected_pr_data["title"] %></h3>

                <span class={"px-2 py-1 rounded-full text-xs #{if @selected_pr_data["state"] == "open", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}>
                  <%= String.capitalize(@selected_pr_data["state"]) %>
                </span>

                <span class="text-sm text-gray-600">by <%= @selected_pr_data["user"]["login"] %></span>

                <span class="text-sm text-gray-600">on <%= format_date(@selected_pr_data["created_at"]) %></span>
              </div>

              <a href={@selected_pr_data["html_url"]} target="_blank" class="inline-flex items-center gap-2 px-4 py-2 bg-black text-white rounded-md hover:bg-gray-800">
                <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z" clip-rule="evenodd"/>
                </svg>
                View on GitHub
              </a>
            </div>

            <%= if @selected_pr_data["body"] do %>
              <div class="prose max-w-none mb-4">
                <.markdown content={@selected_pr_data["body"]} />
              </div>
            <% end %>

            <div class="grid grid-cols-2 gap-4 mb-4">
              <div class="bg-gray-50 p-4 rounded-lg">
                <h4 class="text-md font-medium text-gray-700 mb-2">Base Branch</h4>
                <p class="text-sm text-gray-600"><%= @selected_pr_data["base"]["ref"] %></p>
              </div>
              <div class="bg-gray-50 p-4 rounded-lg">
                <h4 class="text-md font-medium text-gray-700 mb-2">Head Branch</h4>
                <p class="text-sm text-gray-600"><%= @selected_pr_data["head"]["ref"] %></p>
              </div>
            </div>

            <%= if length(@pr_comments) > 0 do %>
              <div class="mt-4">
                <h4 class="text-md font-medium text-gray-700 mb-2">Comments</h4>
                <div class="space-y-4">
                  <%= for {comment, index} <- Enum.with_index(@pr_comments) do %>
                    <div class="bg-gray-50 rounded-lg overflow-hidden">
                      <div
                        class="flex items-center justify-between p-4 cursor-pointer hover:bg-gray-100"
                        phx-click={JS.toggle(to: "#comment-body-#{index}")}
                        aria-expanded="false"
                      >
                        <div class="flex items-center gap-2">
                          <span class="font-medium text-gray-900"><%= comment["user"]["login"] %></span>
                          <span class="text-sm text-gray-500"><%= format_date(comment["created_at"]) %></span>
                          <%= if Map.has_key?(comment, "path") do %>
                            <span class="text-xs px-2 py-1 rounded-full bg-blue-100 text-blue-800">
                              Code review on <%= comment["path"] %>
                            </span>
                          <% else %>
                            <span class="text-xs px-2 py-1 rounded-full bg-green-100 text-green-800">
                              Discussion comment
                            </span>
                          <% end %>
                        </div>
                        <div class="text-gray-500">
                          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 transform transition-transform duration-200" id={"chevron-#{index}"}>
                            <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
                          </svg>
                        </div>
                      </div>
                      <div id={"comment-body-#{index}"} class="border-t border-gray-200 p-4" style="display: none;">
                        <.markdown content={comment["body"]} class="prose prose-sm max-w-none" />
                        <%= if Map.has_key?(comment, "path") and Map.has_key?(comment, "line") do %>
                          <div class="mt-2 text-sm text-gray-500">
                            Line <%= comment["line"] %> <%= if comment["position"], do: "(position: #{comment["position"]})", else: "" %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if length(@pr_files) > 0 do %>
              <div class="mt-4">
                <h4 class="text-md font-medium text-gray-700 mb-2">Pull Request Files</h4>
                <div class="grid grid-cols-2 gap-4">
                  <!-- Left Column: Changed Files -->
                  <div class="border rounded-lg overflow-hidden">
                    <div class="bg-gray-50 px-4 py-2 border-b">
                      <h5 class="text-md font-medium text-gray-700">Changed Files (PR Diff)</h5>
                    </div>
                    <div class="p-4 overflow-y-auto max-h-[70vh]">
                      <div class="space-y-4">
                        <%= for file <- @pr_files do %>
                          <div class="bg-white border rounded-lg overflow-hidden">
                            <div class="bg-gray-50 px-4 py-2 border-b flex justify-between items-center">
                              <span class="text-sm font-medium text-gray-700"><%= file["filename"] %></span>
                              <div class="flex items-center gap-2">
                                <span class="text-xs px-2 py-1 rounded-full bg-blue-100 text-blue-800">
                                  <%= file["changes"] %> changes
                                </span>
                                <span class="text-xs px-2 py-1 rounded-full bg-green-100 text-green-800">
                                  +<%= file["additions"] %>
                                </span>
                                <span class="text-xs px-2 py-1 rounded-full bg-red-100 text-red-800">
                                  -<%= file["deletions"] %>
                                </span>
                              </div>
                            </div>
                            <div class="p-4">
                              <%= if file["patch"] do %>
                                <.format_diff diff={file["patch"]} />
                              <% else %>
                                <div class="text-gray-500 text-center py-4">No diff available</div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <!-- Right Column: Full Files -->
                  <div class="border rounded-lg overflow-hidden">
                    <div class="bg-gray-50 px-4 py-2 border-b">
                      <h5 class="text-md font-medium text-gray-700">Full Updated File</h5>
                    </div>
                    <div class="p-4 overflow-y-auto max-h-[70vh]">
                      <%= if @selected_file do %>
                        <%= if @is_loading_files do %>
                          <div class="text-center p-8">
                            <div class="inline-block animate-spin mr-2 h-6 w-6 text-blue-600 border-2 rounded-full border-solid border-current border-r-transparent" role="status">
                              <span class="sr-only">Loading...</span>
                            </div>
                            <p class="mt-2 text-gray-600">Loading file content...</p>
                          </div>
                        <% else %>
                          <div class="bg-white border rounded-lg overflow-hidden">
                            <div class="bg-gray-50 px-4 py-2 border-b flex justify-between items-center">
                              <span class="text-sm font-medium text-gray-700"><%= @selected_file %></span>
                              <div class="flex items-center gap-2">
                                <span class="text-xs px-2 py-1 rounded-full bg-blue-100 text-blue-800">
                                  <%= @formatted_code.count %> lines
                                </span>
                                <%= if Map.has_key?(@file_changes, @selected_file) do %>
                                  <span class="text-xs px-2 py-1 rounded-full bg-yellow-100 text-yellow-800">
                                    Modified
                                  </span>
                                <% end %>
                                <button
                                  phx-click="force_refresh"
                                  phx-value-filename={@selected_file}
                                  class="text-xs px-2 py-1 rounded-full bg-gray-200 text-gray-700 hover:bg-gray-300"
                                >
                                  Refresh
                                </button>
                              </div>
                            </div>
                            <div class="p-4">
                              <div class="overflow-x-auto text-sm font-mono relative">
                                <div class="flex">
                                  <!-- Line numbers -->
                                  <div class="line-numbers select-none bg-gray-50 border-r border-gray-200 p-2 text-right text-gray-500" style="min-width: 50px; margin-top: -2px;">
                                    <%= for idx <- 1..@formatted_code.count do %>
                                      <div class="leading-5"><%= idx %></div>
                                    <% end %>
                                  </div>
                                  <!-- Code editor -->
                                  <div class="flex-1 relative">
                                    <textarea
                                      id="code-editor"
                                      class="w-full h-full font-mono text-sm p-2 border-0 focus:ring-0 focus:outline-none whitespace-pre"
                                      style="min-height: 200px; resize: vertical; tab-size: 2;"
                                      spellcheck="false"
                                      phx-hook="CodeEditor"
                                      phx-update="ignore"
                                      phx-keyup="handle_code_change"
                                      value={Enum.map_join(@formatted_code.lines, "\n", & &1.content)}
                                    ><%= Enum.map_join(@formatted_code.lines, "\n", & &1.content) %></textarea>
                                  </div>
                                </div>

                                <!-- Action buttons -->
                                <div class="sticky bottom-0 flex mt-2 space-x-2 p-2 bg-gray-100 border-t border-gray-200">
                                  <button
                                    phx-click="save_changes"
                                    class="px-3 py-1 text-sm bg-green-600 text-white rounded hover:bg-green-700"
                                  >
                                    Save Changes
                                  </button>
                                  <button
                                    phx-click="discard_changes"
                                    class="px-3 py-1 text-sm bg-gray-600 text-white rounded hover:bg-gray-700"
                                  >
                                    Discard Changes
                                  </button>
                                </div>
                              </div>
                            </div>
                          </div>
                        <% end %>
                      <% else %>
                        <div class="text-center p-8 text-gray-500">
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 mx-auto text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                          </svg>
                          <p class="mt-2">Select a file to view its full content</p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <%= if @repo do %>
            <div class="bg-white shadow rounded-lg p-4 mb-4">
              <h2 class="text-xl font-bold mb-2">
                <a href={@repo["html_url"]} target="_blank" class="text-blue-500 hover:underline">
                  <%= @repo["full_name"] %>
                </a>
              </h2>
              <p class="text-gray-600 mb-2"><%= @repo["description"] %></p>
              <div class="flex gap-4 text-sm text-gray-500 mb-4">
                <span>⭐ <%= @repo["stargazers_count"] %></span>
                <span>👁️ <%= @repo["watchers_count"] %></span>
                <span>🍴 <%= @repo["forks_count"] %></span>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="bg-gray-50 p-4 rounded-lg">
                  <h3 class="font-semibold mb-2">Repository Info</h3>
                  <ul class="space-y-2">
                    <li><span class="font-medium">Language:</span> <%= @repo["language"] %></li>
                    <li><span class="font-medium">Created:</span> <%= format_date(@repo["created_at"]) %></li>
                    <li><span class="font-medium">Last Updated:</span> <%= format_date(@repo["updated_at"]) %></li>
                    <li><span class="font-medium">Size:</span> <%= format_size(@repo["size"]) %></li>
                  </ul>
                </div>

                <div class="bg-gray-50 p-4 rounded-lg">
                  <h3 class="font-semibold mb-2">Links</h3>
                  <ul class="space-y-2">
                    <li>
                      <a href={@repo["html_url"]} target="_blank" class="text-blue-500 hover:underline">
                        View on GitHub
                      </a>
                    </li>
                    <%= if @repo["homepage"] do %>
                      <li>
                        <a href={@repo["homepage"]} target="_blank" class="text-blue-500 hover:underline">
                          Project Website
                        </a>
                      </li>
                    <% end %>
                  </ul>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp filter_pr(pr, status) do
    case status do
      "open" -> pr["state"] == "open"
      "closed" -> pr["state"] == "closed"
      "all" -> true
    end
  end

  defp format_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        Calendar.strftime(datetime, "%B %d, %Y")
      _ ->
        date_string
    end
  end

  defp format_size(size_kb) do
    cond do
      size_kb >= 1024 * 1024 -> "#{Float.round(size_kb / (1024 * 1024), 2)} GB"
      size_kb >= 1024 -> "#{Float.round(size_kb / 1024, 2)} MB"
      true -> "#{size_kb} KB"
    end
  end

  # Helper function for escaping HTML content (renamed to avoid conflicts)
  defp escape_html(content) when is_binary(content) do
    content
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
  defp escape_html(_), do: ""

  # Helper function to get type as string
  defp typeof(term) do
    cond do
      is_nil(term) -> "nil"
      is_binary(term) -> "binary (string)"
      is_boolean(term) -> "boolean"
      is_number(term) -> "number"
      is_atom(term) -> "atom"
      is_function(term) -> "function"
      is_list(term) -> "list"
      is_tuple(term) -> "tuple"
      is_map(term) -> "map"
      true -> "unknown"
    end
  end

  # Function to format code with line numbers
  defp format_code_with_line_numbers(content) when is_binary(content) do
    lines = String.split(content, ~r/\r?\n/)
    line_count = length(lines)
    line_number_width = String.length("#{line_count}")

    formatted_lines = Enum.with_index(lines, 1)
    |> Enum.map(fn {line, idx} ->
      line_number = String.pad_leading("#{idx}", line_number_width)
      %{number: line_number, content: line, id: "L#{idx}"}
    end)

    %{lines: formatted_lines, count: line_count}
  end
  defp format_code_with_line_numbers(_), do: %{lines: [], count: 0}

  # Enhanced line click handler
  def handle_event("line_click", %{"line" => line_id, "file" => filename}, socket) do

    # Extract line number from line_id (format is "L123")
    line_number = String.replace(line_id, "L", "")

    # Find the content of the selected line
    line_content = case socket.assigns.formatted_code.lines do
      lines when is_list(lines) ->
        Enum.find_value(lines, "", fn line ->
          if line.id == line_id, do: line.content, else: nil
        end)
      _ -> ""
    end

    # Set the selected line in the state
    socket = assign(socket,
      selected_line: line_id,
      edited_content: line_content, # Store the current content
      debug_info: "Selected line #{line_number} in file #{filename}"
    )

    {:noreply, socket}
  end

  # Start editing a line
  def handle_event("start_edit", %{"line" => line_id}, socket) do

    # Get content for this line
    line_content = case socket.assigns.formatted_code.lines do
      lines when is_list(lines) ->
        Enum.find_value(lines, "", fn line ->
          if line.id == line_id, do: line.content, else: nil
        end)
      _ -> ""
    end

    {:noreply, assign(socket,
      editing_line: line_id,
      edited_content: line_content,
      debug_info: "Editing line #{line_id}"
    )}
  end

  # Cancel editing
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket,
      editing_line: nil,
      debug_info: "Editing cancelled"
    )}
  end

  # Deselect the current line
  def handle_event("deselect_line", _params, socket) do
    {:noreply, assign(socket,
      selected_line: nil,
      editing_line: nil,
      debug_info: "Line deselected"
    )}
  end

  # Save the edited line
  def handle_event("save_edit", %{"line" => line_id}, socket) do

    # Get the current file
    file = socket.assigns.selected_file

    # Create or update file changes map
    file_changes = socket.assigns.file_changes
    file_map = Map.get(file_changes, file, %{})
    updated_file_map = Map.put(file_map, line_id, socket.assigns.edited_content)
    updated_changes = Map.put(file_changes, file, updated_file_map)

    # Track changes for future commit
    socket = socket
      |> assign(file_changes: updated_changes)
      |> assign(editing_line: nil)
      |> assign(debug_info: "Changes to line #{line_id} saved")

    {:noreply, socket}
  end

  # Handle keydown events in the editor
  def handle_event("handle_editor_keydown", %{"key" => "Escape"}, socket) do
    # Cancel edit on Escape key
    {:noreply, assign(socket, editing_line: nil)}
  end

  def handle_event("handle_editor_keydown", %{"key" => "Enter", "ctrlKey" => true}, socket) do
    # Save on Ctrl+Enter
    line_id = socket.assigns.editing_line

    {:noreply, assign(socket,
      editing_line: nil,
      debug_info: "Changes to line #{line_id} would be saved via Ctrl+Enter"
    )}
  end

  def handle_event("handle_editor_keydown", _key_info, socket) do
    # For any other key, just continue editing
    {:noreply, socket}
  end

  # Handle form field updates for the editor
  def handle_event("form_update", %{"editor" => %{"content" => content}}, socket) do
    {:noreply, assign(socket, edited_content: content)}
  end

  # Generate an edit suggestion
  def handle_event("suggest_edit", %{"line" => line_id}, socket) do

    # Get content for this line
    line_content = case socket.assigns.formatted_code.lines do
      lines when is_list(lines) ->
        Enum.find_value(lines, "", fn line ->
          if line.id == line_id, do: line.content, else: nil
        end)
      _ -> ""
    end

    # Example suggestion (in a real app, this would come from an AI model)
    suggestion = case line_content do
      "" -> "No content to suggest improvements for."
      content when byte_size(content) > 0 ->
        if String.contains?(content, "TODO") do
          "Consider implementing this TODO item or adding more specific details."
        else
          "Consider adding a comment to explain this line's purpose."
        end
    end

    # Add suggestion to the map of suggestions
    edit_suggestions = Map.put(socket.assigns.edit_suggestions, line_id, suggestion)

    {:noreply, assign(socket,
      edit_suggestions: edit_suggestions,
      debug_info: "Added suggestion for line #{line_id}"
    )}
  end

  # Handle code changes in the textarea
  def handle_event("handle_code_change", %{"value" => content}, socket) do
    # Split content into lines
    lines = String.split(content, "\n")
    line_count = length(lines)

    # Create formatted lines structure
    formatted_lines = Enum.with_index(lines, 1)
    |> Enum.map(fn {line, idx} ->
      %{
        id: "L#{idx}",
        number: "#{idx}",
        content: line
      }
    end)

    # Update the formatted code in socket assigns
    {:noreply, assign(socket,
      formatted_code: %{
        lines: formatted_lines,
        count: line_count
      },
      file_changes: Map.put(socket.assigns.file_changes, socket.assigns.selected_file, content)
    )}
  end

  # Add handlers for save and discard changes
  def handle_event("save_changes", _params, socket) do
    # Here you would typically save the changes to the file
    # For now, we'll just acknowledge the save
    {:noreply, socket}
  end

  def handle_event("discard_changes", _params, socket) do
    # Reset the file changes
    {:noreply, assign(socket,
      file_changes: Map.delete(socket.assigns.file_changes, socket.assigns.selected_file)
    )}
  end
end
