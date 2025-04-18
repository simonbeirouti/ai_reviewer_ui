defmodule AiReviewer.Repo do
  use Ecto.Repo,
    otp_app: :ai_reviewer,
    adapter: Ecto.Adapters.Postgres
end
