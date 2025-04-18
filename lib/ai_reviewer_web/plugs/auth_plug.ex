defmodule AiReviewerWeb.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.VerifiedRoutes

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
