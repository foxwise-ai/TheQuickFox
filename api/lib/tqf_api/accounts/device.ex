defmodule TqfApi.Accounts.Device do
  use Ecto.Schema
  import Ecto.Changeset

  schema "devices" do
    field(:device_uuid, :string)
    field(:device_name, :string)
    field(:auth_token, :string)
    field(:last_seen_at, :utc_datetime)

    belongs_to(:user, TqfApi.Accounts.User)
    has_many(:queries, TqfApi.Usage.Query)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:device_uuid, :device_name, :auth_token, :last_seen_at, :user_id])
    |> validate_required([:device_uuid, :device_name, :user_id])
    |> unique_constraint(:device_uuid)
    |> unique_constraint(:auth_token)
  end
end
