defmodule AiReviewer.CodeReview do
  @moduledoc """
  The CodeReview context.
  """

  import Ecto.Query, warn: false
  alias AiReviewer.Repo
  alias AiReviewer.CodeReview.AntiPattern

  @doc """
  Returns the list of anti_patterns for a specific user.

  ## Examples

      iex> list_anti_patterns(user)
      [%AntiPattern{}, ...]

  """
  def list_anti_patterns(user) do
    AntiPattern
    |> where([ap], ap.user_id == ^user.id)
    |> Repo.all()
  end

  @doc """
  Gets a single anti_pattern.

  Raises `Ecto.NoResultsError` if the Anti pattern does not exist.

  ## Examples

      iex> get_anti_pattern!(123)
      %AntiPattern{}

      iex> get_anti_pattern!(456)
      ** (Ecto.NoResultsError)

  """
  def get_anti_pattern!(id), do: Repo.get!(AntiPattern, id)

  @doc """
  Creates a anti_pattern.

  ## Examples

      iex> create_anti_pattern(%{field: value})
      {:ok, %AntiPattern{}}

      iex> create_anti_pattern(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_anti_pattern(attrs \\ %{}) do
    %AntiPattern{}
    |> AntiPattern.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a anti_pattern.

  ## Examples

      iex> update_anti_pattern(anti_pattern, %{field: new_value})
      {:ok, %AntiPattern{}}

      iex> update_anti_pattern(anti_pattern, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_anti_pattern(%AntiPattern{} = anti_pattern, attrs) do
    anti_pattern
    |> AntiPattern.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a anti_pattern.

  ## Examples

      iex> delete_anti_pattern(anti_pattern)
      {:ok, %AntiPattern{}}

      iex> delete_anti_pattern(anti_pattern)
      {:error, %Ecto.Changeset{}}

  """
  def delete_anti_pattern(%AntiPattern{} = anti_pattern) do
    Repo.delete(anti_pattern)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking anti_pattern changes.

  ## Examples

      iex> change_anti_pattern(anti_pattern)
      %Ecto.Changeset{data: %AntiPattern{}}

  """
  def change_anti_pattern(%AntiPattern{} = anti_pattern, attrs \\ %{}) do
    AntiPattern.changeset(anti_pattern, attrs)
  end

  @doc """
  Gets all active anti-patterns for a specific language and user.

  ## Examples

      iex> get_anti_patterns_by_language("elixir", user)
      [%AntiPattern{}, ...]

  """
  def get_anti_patterns_by_language(language, user) do
    AntiPattern
    |> where([ap], ap.language == ^language and ap.active == true and ap.user_id == ^user.id)
    |> Repo.all()
  end
end
