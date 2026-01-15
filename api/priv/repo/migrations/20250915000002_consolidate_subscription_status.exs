defmodule TqfApi.Repo.Migrations.ConsolidateSubscriptionStatus do
  use Ecto.Migration

  def up do
    # Remove the old boolean columns
    alter table(:users) do
      remove(:has_lifetime_access)
      remove(:has_active_subscription)
    end

    # Drop old indexes
    drop_if_exists(index(:users, [:has_active_subscription]))

    # Create new index on subscription_status for faster lookups
    create(index(:users, [:subscription_status]))
  end

  def down do
    # Add back the old boolean columns
    alter table(:users) do
      add(:has_lifetime_access, :boolean, default: false)
      add(:has_active_subscription, :boolean, default: false)
    end

    # Recreate the old index
    create(index(:users, [:has_active_subscription]))

    # Drop the new index
    drop(index(:users, [:subscription_status]))
  end
end
