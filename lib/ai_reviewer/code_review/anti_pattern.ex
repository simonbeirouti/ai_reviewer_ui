defmodule AiReviewer.CodeReview.AntiPattern do
  use Ecto.Schema
  import Ecto.Changeset

  schema "anti_patterns" do
    field :name, :string
    field :language, :string
    field :content, :string
    field :description, :string
    field :active, :boolean, default: true
    belongs_to :user, AiReviewer.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(anti_pattern, attrs) do
    anti_pattern
    |> cast(attrs, [:name, :language, :content, :description, :active, :user_id])
    |> validate_required([:name, :language, :content, :user_id])
    |> unique_constraint([:name, :language])
    |> foreign_key_constraint(:user_id)
  end
end
