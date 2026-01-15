defmodule TqfApi.Auth.EmailVerification do
  use Ecto.Schema
  import Ecto.Changeset

  @verification_statuses ["pending", "verified", "expired"]

  schema "email_verifications" do
    field(:email, :string)
    field(:verification_token, :string)
    field(:socket_token, :string)
    field(:status, :string, default: "pending")
    field(:expires_at, :utc_datetime)
    field(:verified_at, :utc_datetime)

    belongs_to(:user, TqfApi.Accounts.User)
    belongs_to(:device, TqfApi.Accounts.Device)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email_verification, attrs) do
    email_verification
    |> cast(attrs, [
      :email,
      :verification_token,
      :socket_token,
      :status,
      :expires_at,
      :verified_at,
      :user_id,
      :device_id
    ])
    |> validate_required([:email, :verification_token, :socket_token, :expires_at])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_inclusion(:status, @verification_statuses)
    |> unique_constraint(:verification_token)
    |> unique_constraint(:socket_token)
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  def pending?(%__MODULE__{status: "pending"}), do: true
  def pending?(_), do: false

  def verified?(%__MODULE__{status: "verified"}), do: true
  def verified?(_), do: false
end
