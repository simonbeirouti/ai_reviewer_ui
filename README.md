# AiReviewer

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Copy `config/config.secret.exs.example` to `config/config.secret.exs` and update with your GitHub OAuth credentials
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Configuration

This application requires GitHub OAuth credentials for authentication. To set this up:

1. Create a new OAuth application in your GitHub account settings
2. Copy `config/config.secret.exs.example` to `config/config.secret.exs`
3. Update the new file with your GitHub OAuth credentials
4. Keep this file secure and never commit it to version control

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix