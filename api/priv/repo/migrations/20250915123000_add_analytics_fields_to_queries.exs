defmodule TqfApi.Repo.Migrations.AddAnalyticsFieldsToQueries do
  use Ecto.Migration

  def change do
    alter table(:queries) do
      add :app_name, :string, size: 255
      add :app_bundle_id, :string, size: 255
      add :window_title, :string, size: 500
      add :url, :text
    end
    
    # Add indexes for common queries
    create index(:queries, [:app_bundle_id])
    create index(:queries, [:inserted_at])
  end
end