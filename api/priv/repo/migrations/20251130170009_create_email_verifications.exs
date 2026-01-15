defmodule TqfApi.Repo.Migrations.CreateEmailVerifications do
  use Ecto.Migration

  def change do
    create table(:email_verifications) do
      add :email, :string, null: false
      add :verification_token, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :verified_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all)
      add :device_id, references(:devices, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:email_verifications, [:verification_token])
    create index(:email_verifications, [:email])
    create index(:email_verifications, [:status])
  end
end
