defmodule TqfApi.Repo.Migrations.CreateFeedbackTables do
  use Ecto.Migration

  def change do
    create table(:feedback_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message, :text, null: false
      add :metadata, :map, default: %{}
      add :status, :string, default: "pending", null: false
      add :has_logs, :boolean, default: false, null: false
      add :log_url, :string
      add :admin_notes, :text
      
      add :user_id, references(:users, type: :integer, on_delete: :delete_all), null: false
      
      timestamps()
    end
    
    create index(:feedback_entries, [:user_id])
    create index(:feedback_entries, [:status])
    create index(:feedback_entries, [:inserted_at])
    
    create table(:feedback_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false
      add :size, :integer, null: false
      add :content_type, :string
      add :storage_path, :string, null: false
      add :metadata, :map, default: %{}
      
      add :feedback_id, references(:feedback_entries, type: :binary_id, on_delete: :delete_all), null: false
      
      timestamps()
    end
    
    create index(:feedback_logs, [:feedback_id])
  end
end
