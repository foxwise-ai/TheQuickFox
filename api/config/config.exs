# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tqf_api,
  ecto_repos: [TqfApi.Repo],
  generators: [timestamp_type: :timestamptz]

# Configures the endpoint
config :tqf_api, TqfApiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TqfApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TqfApi.PubSub,
  live_view: [signing_salt: "mYcLxusE"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Stripe configuration
config :stripity_stripe,
  json_library: Jason

# Hammer rate limiter configuration
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: :timer.hours(24), cleanup_interval_ms: :timer.hours(1)]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
