defmodule AiReviewer.GithubService do
  @moduledoc """
  Service module for interacting with GitHub API
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, [
    {"Accept", "application/vnd.github.v3+json"},
    {"User-Agent", "AiReviewer"}
  ]
  plug Tesla.Middleware.JSON

  def search_repositories(query, access_token) do
    case get("/search/repositories", query: [q: query], headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body["items"]}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_user_repositories(access_token) do
    case get("/user/repos", query: [sort: "updated", per_page: 100], headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_repository(owner, repo, access_token) do
    case get("/repos/#{owner}/#{repo}", headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_branches(owner, repo, access_token) do
    case get("/repos/#{owner}/#{repo}/branches", headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_pull_requests(owner, repo, access_token, state \\ "open") do
    IO.inspect(state, label: "Fetching PRs with state")
    case get("/repos/#{owner}/#{repo}/pulls",
      query: [state: state, per_page: 100],
      headers: [{"Authorization", "token #{access_token}"}]
    ) do
      {:ok, %{status: 200, body: body}} ->
        IO.inspect(length(body), label: "Number of PRs fetched")
        IO.inspect(body, label: "PRs data")
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        IO.inspect(body, label: "Error response")
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        IO.inspect(reason, label: "Error")
        {:error, reason}
    end
  end

  def get_pull_request_comments(owner, repo, pr_number, access_token) do
    case get("/repos/#{owner}/#{repo}/pulls/#{pr_number}/comments", headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_pull_request_issue_comments(owner, repo, pr_number, access_token) do
    case get("/repos/#{owner}/#{repo}/issues/#{pr_number}/comments", headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_pull_request_diff(owner, repo, pr_number, access_token) do
    case get("/repos/#{owner}/#{repo}/pulls/#{pr_number}", headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_pull_request_files(owner, repo, pr_number, access_token) do
    case get("/repos/#{owner}/#{repo}/pulls/#{pr_number}/files", headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_diff(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce({[], %{name: nil, chunks: []}}, fn line, {files, current_file} ->
      cond do
        String.starts_with?(line, "diff --git") ->
          new_file = %{name: String.slice(line, 12..-1), chunks: []}
          {files ++ [current_file], new_file}
        String.starts_with?(line, "@@") ->
          new_chunk = %{header: line, lines: []}
          {files, %{current_file | chunks: current_file.chunks ++ [new_chunk]}}
        String.starts_with?(line, "+") ->
          update_current_chunk(current_file, fn chunk ->
            %{chunk | lines: chunk.lines ++ [%{type: :add, content: String.slice(line, 1..-1)}]}
          end)
        String.starts_with?(line, "-") ->
          update_current_chunk(current_file, fn chunk ->
            %{chunk | lines: chunk.lines ++ [%{type: :remove, content: String.slice(line, 1..-1)}]}
          end)
        String.starts_with?(line, " ") ->
          update_current_chunk(current_file, fn chunk ->
            %{chunk | lines: chunk.lines ++ [%{type: :context, content: String.slice(line, 1..-1)}]}
          end)
        true ->
          {files, current_file}
      end
    end)
    |> (fn {files, current_file} ->
      result = files ++ [current_file]
      |> Enum.filter(fn file -> file.name != nil end)
      result
    end).()
  end

  defp update_current_chunk(file, update_fn) do
    case List.last(file.chunks) do
      nil -> {[], file}
      chunk ->
        updated_chunk = update_fn.(chunk)
        updated_chunks = List.replace_at(file.chunks, -1, updated_chunk)
        {[], %{file | chunks: updated_chunks}}
    end
  end
end
