defmodule TqfApi.Repo.Migrations.AddMetadataToQueries do
  use Ecto.Migration

  def change do
    alter table(:queries) do
      add :metadata, :map, default: %{}
    end
  end
end
