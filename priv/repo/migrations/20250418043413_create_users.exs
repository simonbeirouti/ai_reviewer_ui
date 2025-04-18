defmodule AiReviewer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string
      add :github_id, :string
      add :github_token, :string
      add :name, :string
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:github_id])
    create unique_index(:users, [:email])
  end
end
