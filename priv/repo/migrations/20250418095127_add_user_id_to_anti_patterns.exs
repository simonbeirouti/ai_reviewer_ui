defmodule AiReviewer.Repo.Migrations.AddUserIdToAntiPatterns do
  use Ecto.Migration

  def change do
    alter table(:anti_patterns) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create index(:anti_patterns, [:user_id])
  end
end
