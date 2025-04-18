defmodule AiReviewer.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `AiReviewer.Accounts` context.
  """

  @doc """
  Generate a unique user email.
  """
  def unique_user_email, do: "some email#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique user github_id.
  """
  def unique_user_github_id, do: "some github_id#{System.unique_integer([:positive])}"

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        avatar_url: "some avatar_url",
        email: unique_user_email(),
        github_id: unique_user_github_id(),
        github_token: "some github_token",
        name: "some name"
      })
      |> AiReviewer.Accounts.create_user()

    user
  end
end
