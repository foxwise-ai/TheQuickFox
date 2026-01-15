defmodule TqfApi.Repo.Migrations.AddSocketTokenToEmailVerifications do
  use Ecto.Migration

  def change do
    alter table(:email_verifications) do
      add(:socket_token, :string)
    end

    create(unique_index(:email_verifications, [:socket_token]))
  end
end
