defmodule AiReviewer.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :github_id, :string
    field :github_token, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :github_id, :github_token, :name, :avatar_url])
    |> validate_required([:email, :github_id, :github_token, :name, :avatar_url])
    |> unique_constraint(:github_id)
    |> unique_constraint(:email)
  end
end
