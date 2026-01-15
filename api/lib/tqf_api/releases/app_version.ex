defmodule TqfApi.Releases.AppVersion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_versions" do
    field :version, :string
    field :build_number, :string
    field :channel, :string, default: "stable"
    field :release_notes, :string
    field :release_notes_url, :string
    field :download_url, :string
    field :signature, :string
    field :file_size, :integer
    field :minimum_os_version, :string, default: "13.0"
    field :is_critical, :boolean, default: false
    field :published_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(app_version, attrs) do
    app_version
    |> cast(attrs, [:version, :build_number, :channel, :release_notes, :release_notes_url,
                    :download_url, :signature, :file_size, :minimum_os_version, :is_critical, 
                    :published_at])
    |> validate_required([:version, :build_number, :channel, :download_url, :signature, :file_size])
    |> validate_inclusion(:channel, ["stable", "beta"])
    |> unique_constraint([:version, :channel])
  end
end