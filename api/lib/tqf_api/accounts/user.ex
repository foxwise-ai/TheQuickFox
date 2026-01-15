defmodule TqfApi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:email, :string)
    field(:stripe_customer_id, :string)
    field(:trial_queries_used, :integer, default: 0)
    field(:trial_queries_limit, :integer, default: 100_000)
    field(:subscription_status, :string, default: "trial")
    field(:subscription_id, :string)
    field(:subscription_current_period_end, :utc_datetime)
    field(:terms_accepted_at, :utc_datetime)

    has_many(:devices, TqfApi.Accounts.Device)
    has_many(:queries, TqfApi.Usage.Query)

    timestamps(type: :utc_datetime)
  end

  @valid_subscription_statuses ["trial", "active", "canceled", "past_due"]

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :stripe_customer_id,
      :trial_queries_used,
      :trial_queries_limit,
      :subscription_status,
      :subscription_id,
      :subscription_current_period_end,
      :terms_accepted_at
    ])
    |> validate_required([])
    |> unique_constraint(:email)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_number(:trial_queries_limit, greater_than: 0)
    |> validate_inclusion(:subscription_status, @valid_subscription_statuses)
  end

  # Helper functions to derive subscription info from the status string
  def has_active_subscription?(%__MODULE__{subscription_status: status}) do
    status == "active"
  end

  # Deprecated: lifetime access is no longer supported
  def has_lifetime_access?(_user), do: false

  def is_trial?(%__MODULE__{subscription_status: "trial"}), do: true
  def is_trial?(_user), do: false

  def subscription_active?(%__MODULE__{subscription_status: status}) do
    status == "active"
  end
end
