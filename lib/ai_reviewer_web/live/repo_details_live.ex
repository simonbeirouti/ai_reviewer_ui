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

    {:ok, assign(socket,
      repo: repo_data,
      branches: branches,
      pull_requests: pull_requests,
      selected_branch: List.first(branches)["name"],
      selected_pr: nil,
      selected_pr_data: nil,
      pr_comments: [],
      pr_diff: nil,
      pr_status: "open",
      error: if(is_nil(repo_data), do: "Repository not found", else: nil),
      current_user: current_user,
      current_path: "/dashboard/repo/#{repo_name}"
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

  defp fetch_pull_request_data(pr_number, socket) when is_binary(pr_number) do
    fetch_pull_request_data(String.to_integer(pr_number), socket)
  end

  defp fetch_pull_request_data(pr_number, socket) do
    IO.inspect(pr_number, label: "Selected PR number")

    case socket.assigns.current_user do
      %{github_token: token, name: username} ->
        with {:ok, review_comments} <- GithubService.get_pull_request_comments(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, issue_comments} <- GithubService.get_pull_request_issue_comments(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, pr_data} <- GithubService.get_pull_request_diff(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, files} <- GithubService.get_pull_request_files(username, socket.assigns.repo["name"], pr_number, token) do

          # Combine both types of comments
          all_comments = issue_comments ++ review_comments

          {:noreply, assign(socket,
            selected_pr: pr_number,
            pr_comments: all_comments,
            selected_pr_data: pr_data,
            pr_files: files,
            repo: socket.assigns.repo
          )}
        else
          error ->
            IO.inspect(error, label: "Error in PR selection")
            {:noreply, assign(socket,
              selected_pr: pr_number,
              pr_comments: [],
              selected_pr_data: nil,
              pr_files: [],
              repo: socket.assigns.repo
            )}
        end
      _ ->
        {:noreply, assign(socket,
          selected_pr: pr_number,
          pr_comments: [],
          selected_pr_data: nil,
          pr_files: [],
          repo: socket.assigns.repo
        )}
    end
  end

  def render(assigns) do
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
                <h4 class="text-md font-medium text-gray-700 mb-2">Changed Files</h4>
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
                        <.format_diff diff={file["patch"]} />
                      </div>
                    </div>
                  <% end %>
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
end
