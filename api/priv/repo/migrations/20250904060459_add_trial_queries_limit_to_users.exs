defmodule TqfApi.Repo.Migrations.AddTrialQueriesLimitToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :trial_queries_limit, :integer, default: 10, null: false
    end
  end
end
