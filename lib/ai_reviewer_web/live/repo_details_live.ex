defmodule AiReviewerWeb.RepoDetailsLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.GithubService
  alias AiReviewer.Accounts

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

  def handle_event("select_pr", %{"pr" => pr_number}, socket) do
    IO.inspect(pr_number, label: "Selected PR number")

    case socket.assigns.current_user do
      %{github_token: token, name: username} ->
        with {:ok, comments} <- GithubService.get_pull_request_comments(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, pr_data} <- GithubService.get_pull_request_diff(username, socket.assigns.repo["name"], pr_number, token),
             {:ok, files} <- GithubService.get_pull_request_files(username, socket.assigns.repo["name"], pr_number, token) do
          {:noreply, assign(socket,
            selected_pr: pr_number,
            pr_comments: comments,
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
    <div class="flex h-[calc(100vh-4rem)]">
      <!-- Sidebar -->
      <div class="w-1/6 bg-gray-100 p-4 overflow-y-auto">
        <div class="mb-4">
          <a href={~p"/dashboard/repos"} class="text-blue-500 hover:underline">
            ← Back to repositories
          </a>
        </div>

        <div class="mb-4">
          <h3 class="font-semibold mb-2">Branches</h3>
          <select
            class="w-full px-3 py-2 border rounded-lg bg-white"
            phx-change="select_branch"
            name="branch"
          >
            <%= for branch <- @branches do %>
              <option value={branch["name"]} selected={branch["name"] == @selected_branch}>
                <%= branch["name"] %>
              </option>
            <% end %>
          </select>
        </div>

        <div class="mb-4">
          <h3 class="font-semibold mb-2">Pull Request Status</h3>
          <form phx-change="select_pr_status">
            <select
              class="w-full px-3 py-2 border rounded-lg bg-white"
              name="status"
            >
              <option value="open" selected={@pr_status == "open"}>Open</option>
              <option value="closed" selected={@pr_status == "closed"}>Closed</option>
              <option value="all" selected={@pr_status == "all"}>All</option>
            </select>
          </form>
        </div>

        <div class="mb-4">
          <h3 class="font-semibold mb-2">Pull Requests</h3>
          <div class="space-y-2">
            <%= if length(@pull_requests) == 0 do %>
              <div class="text-gray-500 text-center py-4">
                No pull requests found for status: <%= @pr_status %>
              </div>
            <% else %>
              <%= for pr <- @pull_requests do %>
                <div
                  class={"p-2 rounded-lg cursor-pointer #{if pr["number"] == @selected_pr, do: "bg-blue-100", else: "hover:bg-gray-200"}"}
                  phx-click="select_pr"
                  phx-value-pr={pr["number"]}
                >
                  <div class="font-medium">#<%= pr["number"] %> <%= pr["title"] %></div>
                  <div class="text-sm flex flex-col text-gray-600">
                    <p><%= pr["user"]["login"] %></p>
                    <p><%= format_date(pr["created_at"]) %></p>
                    <p class={"font-medium #{if pr["state"] == "open", do: "text-green-600", else: "text-red-600"}"}>
                      <%= String.capitalize(pr["state"]) %>
                    </p>
                  </div>
                </div>
              <% end %>
            <% end %>
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
            <%!-- <div class="flex justify-between items-start mb-4">
              <div>
                <h3 class="text-lg font-medium text-gray-900">#<%= @selected_pr_data["number"] %> <%= @selected_pr_data["title"] %></h3>
                <div class="flex items-center gap-2 text-sm text-gray-600 mt-1">
                  <span class={"px-2 py-1 rounded-full text-xs #{if @selected_pr_data["state"] == "open", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}>
                    <%= String.capitalize(@selected_pr_data["state"]) %>
                  </span>
                  <span>by <%= @selected_pr_data["user"]["login"] %></span>
                  <span>on <%= format_date(@selected_pr_data["created_at"]) %></span>
                </div>
              </div>
              <a href={@selected_pr_data["html_url"]} target="_blank" class="text-blue-500 hover:underline">
                View on GitHub
              </a>
            </div> --%>

            <%= if @selected_pr_data["body"] do %>
              <div class="prose max-w-none mb-4">
                <%= @selected_pr_data["body"] %>
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
                  <%= for comment <- @pr_comments do %>
                    <div class="bg-gray-50 p-4 rounded-lg">
                      <div class="flex items-center gap-2 mb-2">
                        <span class="font-medium text-gray-900"><%= comment["user"]["login"] %></span>
                        <span class="text-sm text-gray-500"><%= format_date(comment["created_at"]) %></span>
                      </div>
                      <p class="text-gray-600"><%= comment["body"] %></p>
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
                        <div class="font-mono text-sm whitespace-pre overflow-x-auto">
                          <%= file["patch"] %>
                        </div>
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
