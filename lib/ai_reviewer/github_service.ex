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
    case get("/repos/#{owner}/#{repo}/pulls",
      query: [state: state, per_page: 100],
      headers: [{"Authorization", "token #{access_token}"}]
    ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(body)}"}
      {:error, reason} ->
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

  def get_file_content(owner, repo, path, ref, access_token) do
    url = "/repos/#{owner}/#{repo}/contents/#{path}?ref=#{ref}"

    case get(url, headers: [{"Authorization", "token #{access_token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"content" => content, "encoding" => "base64"} ->
            cleaned_content = String.replace(content || "", ~r/[\r\n]/, "")
            try do
              decoded = Base.decode64!(cleaned_content)
              {:ok, decoded}
            rescue
              e ->
                {:error, "Error decoding file content: #{inspect(e)}"}
            end
          _ ->
            {:error, "Invalid response format"}
        end
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
          new_file = %{name: String.slice(line, 12..-1//1), chunks: []}
          {files ++ [current_file], new_file}
        String.starts_with?(line, "@@") ->
          new_chunk = %{header: line, lines: []}
          {files, %{current_file | chunks: current_file.chunks ++ [new_chunk]}}
        String.starts_with?(line, "+") ->
          update_current_chunk(current_file, fn chunk ->
            %{chunk | lines: chunk.lines ++ [%{type: :add, content: String.slice(line, 1..-1//1)}]}
          end)
        String.starts_with?(line, "-") ->
          update_current_chunk(current_file, fn chunk ->
            %{chunk | lines: chunk.lines ++ [%{type: :remove, content: String.slice(line, 1..-1//1)}]}
          end)
        String.starts_with?(line, " ") ->
          update_current_chunk(current_file, fn chunk ->
            %{chunk | lines: chunk.lines ++ [%{type: :context, content: String.slice(line, 1..-1//1)}]}
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

  @doc """
  Commits a file change to a branch
  """
  def commit_file(username, repo, branch, path, content, message, token) do
    url = "/repos/#{username}/#{repo}/contents/#{path}"

    # First get the current file to get its SHA
    case get_file_content(username, repo, path, branch, token) do
      {:ok, current_content} ->
        # Only commit if content has changed
        if current_content != content do
          client = Tesla.client([
            {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{token}"}]}
          ])

          body = %{
            message: message,
            content: Base.encode64(content),
            sha: get_file_sha(username, repo, path, branch, token),
            branch: branch
          }

          case put(client, url, body) do
            {:ok, %{status: status}} when status in 200..201 ->
              {:ok, "File committed successfully"}
            {:ok, %{status: status, body: body}} ->
              {:error, "GitHub API error: #{status} - #{inspect(body)}"}
            {:error, reason} ->
              {:error, "HTTP error: #{inspect(reason)}"}
          end
        else
          {:ok, "No changes to commit"}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a file's SHA from GitHub
  """
  def get_file_sha(username, repo, path, branch, token) do
    url = "/repos/#{username}/#{repo}/contents/#{path}"
    client = Tesla.client([
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{token}"}]}
    ])

    case get(client, url, query: [ref: branch]) do
      {:ok, %{status: 200, body: body}} ->
        body["sha"]
      _ ->
        nil
    end
  end

  @doc """
  Creates a new pull request
  """
  def create_pull_request(username, repo, title, body, base, head, token) do
    url = "/repos/#{username}/#{repo}/pulls"
    client = Tesla.client([
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{token}"}]}
    ])

    pull_request_body = %{
      title: title,
      body: body,
      head: head,
      base: base
    }

    case post(client, url, pull_request_body) do
      {:ok, %{status: status, body: response_body}} when status in 200..201 ->
        {:ok, response_body["html_url"]}
      {:ok, %{status: status, body: error_body}} ->
        {:error, "GitHub API error: #{status} - #{inspect(error_body)}"}
      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end
end
