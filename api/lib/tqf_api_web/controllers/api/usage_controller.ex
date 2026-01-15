defmodule TqfApiWeb.Api.UsageController do
  use TqfApiWeb, :controller

  alias TqfApi.{Accounts, Usage, Repo}

  action_fallback(TqfApiWeb.FallbackController)

  def track(conn, params) do
    device = conn.assigns.current_device
    
    # Check if user has accepted terms of service
    case check_terms_acceptance(device.user) do
      {:error, :terms_not_accepted} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Terms of service must be accepted before using the service", terms_required: true})
      
      {:ok, user} ->
        # Extract mode (required) and optional analytics fields
        mode = params["mode"]
        app_name = params["app_name"]
        app_bundle_id = params["app_bundle_id"]
        window_title = params["window_title"]
        url = params["url"]
        metadata = params["metadata"] || %{}

        with {:ok, user} <- check_quota(user),
             {:ok, query} <- track_query(device, mode, app_name, app_bundle_id, window_title, url, metadata),
             {:ok, updated_user} <- increment_trial_usage(user) do
          conn
          |> put_status(:created)
          |> json(%{
            data: %{
              query_id: query.id,
              tracked_at: query.inserted_at,
              trial_queries_remaining: max(0, updated_user.trial_queries_limit - updated_user.trial_queries_used)
            }
          })
        else
          {:error, :quota_exceeded} ->
            conn
            |> put_status(:payment_required)
            |> json(%{error: "Trial quota exceeded", upgrade_required: true})
        end
    end
  end

  def show(conn, _params) do
    device = conn.assigns.current_device
    queries_today = Usage.count_queries_today(device.user_id)
    
    require Logger
    Logger.info("UsageController.show called for user #{device.user_id}")
    
    # Get subscription details
    subscription_details = case TqfApi.Billing.StripeService.get_subscription_details(device.user) do
      {:ok, details} -> 
        Logger.info("Got subscription details: #{inspect(details)}")
        details
      error -> 
        Logger.error("Failed to get subscription details: #{inspect(error)}")
        nil
    end

    conn
    |> json(%{
      data: %{
        trial_queries_used: device.user.trial_queries_used,
        trial_queries_remaining: max(0, device.user.trial_queries_limit - device.user.trial_queries_used),
        queries_today: queries_today,
        has_subscription: TqfApi.Billing.StripeService.has_active_subscription?(device.user),
        has_lifetime_access: TqfApi.Accounts.User.has_lifetime_access?(device.user),
        subscription_details: subscription_details
      }
    })
  end

  defp check_terms_acceptance(user) do
    if user.terms_accepted_at do
      {:ok, user}
    else
      {:error, :terms_not_accepted}
    end
  end

  defp check_quota(user) do
    alias TqfApi.Billing.StripeService

    # Check if user has active subscription
    if StripeService.has_active_subscription?(user) do
      {:ok, user}
    else
      # Check trial quota
      if user.trial_queries_used < user.trial_queries_limit do
        {:ok, user}
      else
        {:error, :quota_exceeded}
      end
    end
  end

  defp track_query(device, mode, app_name, app_bundle_id, window_title, url, metadata) do
    Usage.create_query(%{
      user_id: device.user_id,
      device_id: device.id,
      mode: mode,
      app_name: app_name,
      app_bundle_id: app_bundle_id,
      window_title: window_title,
      url: url,
      metadata: metadata
    })
  end

  defp increment_trial_usage(user) do
    alias TqfApi.Billing.StripeService

    # Only increment if not a subscriber and still in trial
    if !StripeService.has_active_subscription?(user) && user.trial_queries_used < user.trial_queries_limit do
      Accounts.update_user(user, %{trial_queries_used: user.trial_queries_used + 1})
    else
      {:ok, user}
    end
  end
end
