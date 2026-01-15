defmodule TqfApi.Feedback.FeedbackEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "feedback_entries" do
    field :message, :string
    field :metadata, :map, default: %{}
    field :status, :string, default: "pending"
    field :has_logs, :boolean, default: false
    field :log_url, :string
    field :admin_notes, :string
    
    belongs_to :user, TqfApi.Accounts.User, type: :integer
    has_many :logs, TqfApi.Feedback.FeedbackLog
    
    timestamps()
  end

  @doc false
  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [:user_id, :message, :metadata, :status, :has_logs, :log_url, :admin_notes])
    |> validate_required([:user_id, :message])
    |> validate_length(:message, min: 1, max: 5000)
    |> validate_inclusion(:status, ["pending", "reviewed", "resolved", "closed"])
    |> foreign_key_constraint(:user_id)
  end
end