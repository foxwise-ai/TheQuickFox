defmodule TqfApi.Repo.Migrations.AddAppVersionsAndBetaFlag do
  use Ecto.Migration

  def change do
    # Create app_versions table
    create table(:app_versions) do
      add :version, :string, null: false
      add :build_number, :string, null: false
      add :channel, :string, null: false, default: "stable"
      add :release_notes, :text
      add :release_notes_url, :string
      add :download_url, :string, null: false
      add :signature, :string, null: false
      add :file_size, :bigint, null: false
      add :minimum_os_version, :string, default: "13.0"
      add :is_critical, :boolean, default: false
      add :published_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:app_versions, [:version, :channel])
    create index(:app_versions, [:channel, :published_at])

    # Add beta tester flag to users
    alter table(:users) do
      add :is_beta_tester, :boolean, default: false
    end

    create index(:users, [:is_beta_tester])
  end
end
