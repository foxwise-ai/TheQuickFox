defmodule TqfApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize ETS table for reminders
    :ets.new(:reminders, [:set, :public, :named_table])

    children = [
      TqfApiWeb.Telemetry,
      TqfApi.Repo,
      {DNSCluster, query: Application.get_env(:tqf_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TqfApi.PubSub},
      # Start a worker by calling: TqfApi.Worker.start_link(arg)
      # {TqfApi.Worker, arg},
      # Start to serve requests, typically the last entry
      TqfApiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TqfApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TqfApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
