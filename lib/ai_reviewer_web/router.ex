defmodule AiReviewerWeb.Router do
  use AiReviewerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AiReviewerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug AiReviewerWeb.FetchCurrentUserPlug
    plug :assign_current_path
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug AiReviewerWeb.AuthPlug
  end

  defp assign_current_path(conn, _opts) do
    assign(conn, :current_path, conn.request_path)
  end

  scope "/", AiReviewerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", AiReviewerWeb do
    pipe_through [:browser, :auth]

    get "/dashboard", PageController, :dashboard
    live "/dashboard/repos", RepoSearchLive
    live "/dashboard/repo/:repo_name", RepoDetailsLive
    live "/dashboard/patterns", PatternsLive
  end

  scope "/auth", AiReviewerWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", AiReviewerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ai_reviewer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AiReviewerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
