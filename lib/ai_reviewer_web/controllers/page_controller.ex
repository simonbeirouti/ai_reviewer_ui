defmodule AiReviewerWeb.PageController do
  use AiReviewerWeb, :controller

  def home(conn, _params) do
    render(conn, :home, current_user: conn.assigns[:current_user])
  end

  def dashboard(conn, _params) do
    render(conn, :dashboard, current_user: conn.assigns[:current_user])
  end
end
