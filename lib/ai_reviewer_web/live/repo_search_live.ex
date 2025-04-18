defmodule AiReviewerWeb.RepoSearchLive do
  use AiReviewerWeb, :live_view
  alias AiReviewer.GithubService
  alias AiReviewer.Accounts

  def mount(_params, session, socket) do
    current_user = if session["user_id"] do
      Accounts.get_user!(session["user_id"])
    end

    repositories = case current_user do
      %{github_token: token} ->
        case GithubService.get_user_repositories(token) do
          {:ok, repos} ->
            repos
            |> Enum.map(fn repo ->
              %{
                "name" => repo["name"],
                "full_name" => repo["full_name"],
                "owner" => %{"login" => repo["owner"]["login"]},
                "html_url" => repo["html_url"],
                "description" => repo["description"],
                "stargazers_count" => repo["stargazers_count"],
                "watchers_count" => repo["watchers_count"],
                "forks_count" => repo["forks_count"]
              }
            end)
          _ -> []
        end
      _ -> []
    end

    {:ok, assign(socket,
      repositories: repositories,
      error: nil,
      current_user: current_user,
      current_path: "/dashboard/repos"
    )}
  end

  def handle_event("select_repo", %{"repo" => repo_name}, socket) do
    case repo_name do
      "" ->
        {:noreply, socket}
      name ->
        {:noreply, redirect(socket, to: "/dashboard/repo/#{name}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-4">
      <h1 class="text-2xl font-bold mb-4">Select a Repository</h1>

      <form phx-change="select_repo" class="mb-4">
        <select
          class="w-full px-4 py-2 border rounded-lg bg-white"
          name="repo"
        >
          <option value="">Select a repository...</option>
          <%= for repo <- @repositories do %>
            <option value={repo["name"]}>
              <%= repo["name"] %>
            </option>
          <% end %>
        </select>
      </form>

      <%= if @error do %>
        <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          <%= @error %>
        </div>
      <% end %>
    </div>
    """
  end
end
