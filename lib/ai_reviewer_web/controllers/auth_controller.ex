defmodule AiReviewerWeb.AuthController do
  use AiReviewerWeb, :controller
  plug Ueberauth

  alias AiReviewer.Accounts

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      github_id: to_string(auth.uid),
      email: auth.info.email,
      name: auth.info.name || auth.info.nickname,
      avatar_url: auth.info.image,
      github_token: auth.credentials.token
    }

    case Accounts.get_or_create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully authenticated.")
        |> redirect(to: ~p"/dashboard/repos")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Error authenticating with GitHub.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end
end
