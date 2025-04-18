defmodule AiReviewerWeb.ReposLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.Accounts
  alias AiReviewer.GithubService

  def mount(_params, session, socket) do
    current_user = if session["user_id"] do
      Accounts.get_user!(session["user_id"])
    end

    repos = case current_user do
      %{github_token: token} ->
        case GithubService.get_user_repositories(token) do
          {:ok, repos} -> repos
          _ -> []
        end
      _ -> []
    end

    {:ok, assign(socket,
      repos: repos,
      current_user: current_user,
      page_title: "Your Repositories",
      current_path: "/dashboard/repos"
    )}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100">
      <!-- Header -->
      <div class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex justify-between items-center">
            <h1 class="text-2xl font-bold text-gray-900">Your Repositories</h1>
            <div class="flex items-center">
              <span class="text-gray-600"><%= @current_user.name %></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-4 py-5 sm:p-6">
            <%= if length(@repos) > 0 do %>
              <div class="grid gap-6">
                <%= for repo <- @repos do %>
                  <div class="border border-gray-200 rounded-lg p-4 hover:border-blue-500 transition-colors duration-200">
                    <div class="flex items-center justify-between">
                      <div>
                        <h3 class="text-lg font-medium text-gray-900">
                          <.link
                            navigate={~p"/dashboard/repo/#{repo["name"]}"}
                            class="hover:text-blue-600"
                          >
                            <%= repo["name"] %>
                          </.link>
                        </h3>
                        <p class="mt-1 text-sm text-gray-500">
                          <%= repo["description"] || "No description available" %>
                        </p>
                      </div>
                      <div class="flex items-center space-x-4 text-sm text-gray-500">
                        <div class="flex items-center">
                          <svg class="h-4 w-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M10 2a1 1 0 00-1 1v1.323l-3.954 1.582a1 1 0 00-.646.933v4.286a1 1 0 00.646.933l3.954 1.582V15a1 1 0 002 0v-1.323l3.954-1.582a1 1 0 00.646-.933V6.838a1 1 0 00-.646-.933l-3.954-1.582V3a1 1 0 00-1-1zm0 2.618l3.954 1.582v4.286L10 12.068V4.618z" clip-rule="evenodd" />
                          </svg>
                          <%= repo["language"] || "Unknown" %>
                        </div>
                        <div class="flex items-center">
                          <svg class="h-4 w-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M10 1.944A11.954 11.954 0 012.166 5C2.056 5.649 2 6.319 2 7c0 5.225 3.34 9.67 8 11.317C14.66 16.67 18 12.225 18 7c0-.682-.057-1.35-.166-2.001A11.954 11.954 0 0110 1.944zM11 14a1 1 0 11-2 0 1 1 0 012 0zm0-7a1 1 0 10-2 0v3a1 1 0 102 0V7z" clip-rule="evenodd" />
                          </svg>
                          Private: <%= if repo["private"], do: "Yes", else: "No" %>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-12">
                <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                <h3 class="mt-2 text-sm font-medium text-gray-900">No repositories found</h3>
                <p class="mt-1 text-sm text-gray-500">
                  Connect your GitHub account to see your repositories here.
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
