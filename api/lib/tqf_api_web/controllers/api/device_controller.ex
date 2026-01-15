defmodule TqfApiWeb.Api.DeviceController do
  use TqfApiWeb, :controller

  alias TqfApi.Accounts
  alias TqfApi.Repo

  action_fallback(TqfApiWeb.FallbackController)

  def register(conn, %{"device_uuid" => device_uuid, "device_name" => device_name}) do
    device =
      case Accounts.get_device_by_uuid(device_uuid) do
        nil ->
          # New device - create user and device with auth token
          {:ok, user} = Accounts.create_user(%{})
          auth_token = generate_auth_token()

          {:ok, device} =
            Accounts.create_device(%{
              user_id: user.id,
              device_uuid: device_uuid,
              device_name: device_name,
              auth_token: auth_token,
              last_seen_at: DateTime.utc_now()
            })

          device

        existing_device ->
          # Existing device - update last seen
          {:ok, device} =
            Accounts.update_device(existing_device, %{
              last_seen_at: DateTime.utc_now()
            })

          device
      end

    device = Repo.preload(device, :user)
    
    # Check subscription status
    has_subscription = TqfApi.Billing.StripeService.has_active_subscription?(device.user)
    
    # Get subscription details if needed
    subscription_details = case TqfApi.Billing.StripeService.get_subscription_details(device.user) do
      {:ok, details} -> details
      _ -> nil
    end

    conn
    |> put_status(:ok)
    |> json(%{
      data: %{
        device_id: device.id,
        user_id: device.user_id,
        auth_token: device.auth_token,
        trial_queries_used: device.user.trial_queries_used,
        trial_queries_remaining: max(0, device.user.trial_queries_limit - device.user.trial_queries_used),
        has_subscription: has_subscription,
        has_lifetime_access: TqfApi.Accounts.User.has_lifetime_access?(device.user),
        subscription_details: subscription_details,
        terms_accepted_at: device.user.terms_accepted_at
      }
    })
  end

  def accept_terms(conn, params) do
    device = conn.assigns.current_device
    user = device.user

    # Build update attrs with terms acceptance timestamp and optional email
    update_attrs = %{terms_accepted_at: DateTime.utc_now()}
    update_attrs = case params["email"] do
      email when is_binary(email) and email != "" -> Map.put(update_attrs, :email, email)
      _ -> update_attrs
    end

    # Update user's terms acceptance timestamp and email
    case Accounts.update_user(user, update_attrs) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            terms_accepted_at: updated_user.terms_accepted_at,
            email: updated_user.email
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to accept terms", details: changeset.errors})
    end
  end

  defp generate_auth_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64()
    |> binary_part(0, 32)
  end
end
