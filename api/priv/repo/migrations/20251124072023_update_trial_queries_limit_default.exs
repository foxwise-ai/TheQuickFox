defmodule TqfApi.Repo.Migrations.UpdateTrialQueriesLimitDefault do
  use Ecto.Migration

  def change do
    # Update the default value for new records
    alter table(:users) do
      modify :trial_queries_limit, :integer, default: 100_000, null: false
    end
  end
end
