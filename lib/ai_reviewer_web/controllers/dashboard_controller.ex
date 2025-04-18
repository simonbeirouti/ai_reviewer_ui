defmodule AiReviewerWeb.DashboardController do
  use AiReviewerWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/dashboard/repos")
  end
end
