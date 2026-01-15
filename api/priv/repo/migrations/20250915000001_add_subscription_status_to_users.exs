defmodule TqfApi.Repo.Migrations.AddSubscriptionStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :has_active_subscription, :boolean, default: false
      add :subscription_id, :string
      add :subscription_status, :string
      add :subscription_current_period_end, :timestamptz
    end
    
    # Add index for faster lookups
    create index(:users, [:has_active_subscription])
    create index(:users, [:subscription_id])
  end
end