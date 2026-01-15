defmodule TqfApi.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:stripe_customer_id, :string)
      add(:trial_queries_used, :integer, default: 0)

      timestamps(type: :timestamptz)
    end

    create(index(:users, [:stripe_customer_id]))
  end
end
