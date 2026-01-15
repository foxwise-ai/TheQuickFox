defmodule TqfApi.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TqfApi.Accounts` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        stripe_customer_id: "some stripe_customer_id"
      })
      |> TqfApi.Accounts.create_user()

    user
  end

  @doc """
  Generate a unique device auth_token.
  """
  def unique_device_auth_token, do: "some auth_token#{System.unique_integer([:positive])}"

  @doc """
  Generate a device.
  """
  def device_fixture(attrs \\ %{}) do
    {:ok, device} =
      attrs
      |> Enum.into(%{
        auth_token: unique_device_auth_token(),
        device_name: "some device_name",
        device_uuid: "some device_uuid",
        last_seen_at: ~U[2025-08-26 16:05:00Z]
      })
      |> TqfApi.Accounts.create_device()

    device
  end
end
