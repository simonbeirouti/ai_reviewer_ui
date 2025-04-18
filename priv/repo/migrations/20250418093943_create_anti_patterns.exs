defmodule AiReviewer.Repo.Migrations.CreateAntiPatterns do
  use Ecto.Migration

  def change do
    create table(:anti_patterns) do
      add :name, :string, null: false
      add :language, :string, null: false
      add :content, :text, null: false
      add :description, :text
      add :active, :boolean, default: true

      timestamps()
    end

    create index(:anti_patterns, [:language])
    create unique_index(:anti_patterns, [:name, :language])
  end
end
