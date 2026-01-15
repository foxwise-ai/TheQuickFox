defmodule TqfApi.Repo.Migrations.CreateQueries do
  use Ecto.Migration

  def change do
    create table(:queries) do
      add(:mode, :string)
      add(:user_id, references(:users, on_delete: :nothing))
      add(:device_id, references(:devices, on_delete: :nothing))

      timestamps(type: :timestamptz)
    end

    create(index(:queries, [:user_id]))
    create(index(:queries, [:device_id]))
  end
end
