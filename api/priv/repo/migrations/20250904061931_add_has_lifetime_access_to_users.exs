defmodule TqfApi.Repo.Migrations.AddHasLifetimeAccessToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :has_lifetime_access, :boolean, default: false, null: false
    end
  end
end
