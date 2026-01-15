defmodule TqfApi.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices) do
      add(:device_uuid, :string)
      add(:device_name, :string)
      add(:auth_token, :string)
      add(:last_seen_at, :timestamptz)
      add(:user_id, references(:users, on_delete: :nothing))

      timestamps(type: :timestamptz)
    end

    create(unique_index(:devices, [:auth_token]))
    create(index(:devices, [:user_id]))
  end
end
