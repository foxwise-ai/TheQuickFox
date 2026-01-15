defmodule TqfApi.Feedback.FeedbackLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "feedback_logs" do
    field :filename, :string
    field :size, :integer
    field :content_type, :string
    field :storage_path, :string
    field :metadata, :map, default: %{}
    
    belongs_to :feedback, TqfApi.Feedback.FeedbackEntry, foreign_key: :feedback_id
    
    timestamps()
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:feedback_id, :filename, :size, :content_type, :storage_path, :metadata])
    |> validate_required([:feedback_id, :filename, :size, :storage_path])
    |> foreign_key_constraint(:feedback_id)
  end
end