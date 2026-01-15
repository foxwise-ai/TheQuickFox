defmodule TqfApi.Releases do
  @moduledoc """
  The Releases context.
  """

  import Ecto.Query, warn: false
  alias TqfApi.Repo
  alias TqfApi.Releases.AppVersion

  @doc """
  Gets the latest stable app version
  """
  def get_latest_stable_version do
    AppVersion
    |> where([v], v.channel == "stable")
    |> where([v], not is_nil(v.published_at))
    |> where([v], v.published_at <= ^DateTime.utc_now())
    |> order_by([v], desc: v.published_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the latest beta app version
  """
  def get_latest_beta_version do
    AppVersion
    |> where([v], v.channel == "beta")
    |> where([v], not is_nil(v.published_at))
    |> where([v], v.published_at <= ^DateTime.utc_now())
    |> order_by([v], desc: v.published_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the latest version for a specific channel
  """
  def get_latest_version(channel) do
    AppVersion
    |> where([v], v.channel == ^channel)
    |> where([v], not is_nil(v.published_at))
    |> where([v], v.published_at <= ^DateTime.utc_now())
    |> order_by([v], desc: v.published_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a new app version
  """
  def create_app_version(attrs \\ %{}) do
    %AppVersion{}
    |> AppVersion.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all app versions
  """
  def list_app_versions do
    AppVersion
    |> order_by([v], desc: v.published_at)
    |> Repo.all()
  end
end