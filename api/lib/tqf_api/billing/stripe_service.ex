defmodule TqfApi.Billing.StripeService do
  @moduledoc """
  Handles all Stripe-related operations
  """

  alias Stripe.{Customer, Checkout.Session, Subscription}
  alias TqfApi.{Accounts, Repo}
  require Logger

  def monthly_price_id,
    do: System.get_env("STRIPE_MONTHLY_PRICE_ID") || "price_monthly_placeholder"

  def yearly_price_id, do: System.get_env("STRIPE_YEARLY_PRICE_ID") || "price_yearly_placeholder"

  @doc """
  Checks if Stripe is properly configured
  """
  def configured? do
    api_key = Application.get_env(:stripity_stripe, :api_key)
    api_key != nil && api_key != ""
  end

  @doc """
  Creates a Stripe checkout session for the user
  Email will be collected during checkout if not already present
  """
  def create_checkout_session(user, price_type, success_url, cancel_url) do
    unless configured?() do
      Logger.error(
        "Stripe is not configured! API key: #{inspect(Application.get_env(:stripity_stripe, :api_key))}"
      )

      {:error, "Stripe is not configured"}
    else
      with {:ok, customer} <- ensure_stripe_customer(user),
           {:ok, session} <-
             create_session(customer.id, user.email, price_type, success_url, cancel_url) do
        {:ok, session}
      end
    end
  end

  @doc """
  Creates a Stripe checkout session using a specific price ID
  This is the preferred method as it's completely agnostic
  """
  def create_checkout_session_with_price_id(user, price_id, success_url, cancel_url) do
    unless configured?() do
      {:error, "Stripe is not configured"}
    else
      with {:ok, customer} <- ensure_stripe_customer(user),
           {:ok, session} <-
             create_session_with_price_id(
               customer.id,
               user.email,
               price_id,
               success_url,
               cancel_url
             ) do
        {:ok, session}
      end
    end
  end

  @doc """
  Creates or retrieves a Stripe customer for the user
  """
  def ensure_stripe_customer(user) do
    # Check for nil or empty string
    if is_nil(user.stripe_customer_id) || user.stripe_customer_id == "" do
      Logger.info("Creating new Stripe customer for user #{user.id}")

      # Create new Stripe customer
      create_customer_params = %{
        metadata: %{
          user_id: to_string(user.id)
        }
      }

      # Add email if available
      create_customer_params =
        if user.email do
          Map.put(create_customer_params, :email, user.email)
        else
          create_customer_params
        end

      case Customer.create(create_customer_params) do
        {:ok, customer} ->
          # Update user with Stripe customer ID
          {:ok, _user} = Accounts.update_user(user, %{stripe_customer_id: customer.id})
          {:ok, customer}

        error ->
          error
      end
    else
      # Retrieve existing customer
      Customer.retrieve(user.stripe_customer_id)
    end
  end

  @doc """
  Checks if user has active subscription or lifetime access
  """
  def has_active_subscription?(user) do
    # Check local database fields - no Stripe API calls
    TqfApi.Accounts.User.has_active_subscription?(user)
  end

  @doc """
  Gets detailed subscription info including pricing
  """
  def get_subscription_details(user) do
    Logger.info("get_subscription_details for user #{user.id}: status=#{user.subscription_status}, sub_id=#{user.subscription_id}")

    cond do
      TqfApi.Accounts.User.has_active_subscription?(user) ->
        Logger.info("User #{user.id} has active subscription")
        # Try to fetch from Stripe if we have a subscription ID
        if user.subscription_id do
          Logger.info("Fetching subscription #{user.subscription_id} from Stripe")
          case Subscription.retrieve(user.subscription_id) do
            {:ok, subscription} ->
              Logger.info("Retrieved subscription status: #{subscription.status}")
              # Verify the subscription is actually active
              if subscription.status in ["active", "trialing"] do
                price = hd(subscription.items.data).price
                Logger.info("Returning active subscription details for user #{user.id}")
                {:ok, %{
                  type: "subscription",
                  interval: price.recurring.interval,
                  interval_count: price.recurring.interval_count,
                  amount: price.unit_amount,
                  currency: price.currency,
                  cancel_at_period_end: subscription.cancel_at_period_end
                }}
              else
                # Subscription exists but isn't active - sync the status
                Logger.warning("User #{user.id} has inactive subscription #{subscription.id} with status: #{subscription.status}")
                # Return trial status since subscription isn't actually active
                {:ok, %{type: "trial", trial_queries_remaining: max(0, user.trial_queries_limit - user.trial_queries_used)}}
              end
            {:error, %Stripe.Error{code: "resource_missing"}} -> 
              # Subscription doesn't exist in Stripe - user data is out of sync
              Logger.error("User #{user.id} has subscription_id #{user.subscription_id} but it doesn't exist in Stripe")
              {:ok, %{type: "subscription"}}
            error -> 
              Logger.error("Failed to fetch subscription for user #{user.id}: #{inspect(error)}")
              # Fallback if we can't fetch from Stripe
              {:ok, %{type: "subscription"}}
          end
        else
          # User has active subscription status but no subscription_id
          # This shouldn't happen but handle it gracefully
          Logger.warning("User #{user.id} has active subscription status but no subscription_id")
          {:ok, %{type: "subscription"}}
        end
        
      true ->
        Logger.info("User #{user.id} falling through to trial status")
        {:ok, %{type: "trial", trial_queries_remaining: max(0, user.trial_queries_limit - user.trial_queries_used)}}
    end
  end

  @doc """
  Retrieves subscription status for a user
  """
  def get_subscription_status(user) do
    case user.stripe_customer_id do
      nil ->
        {:ok,
         %{
           active: false,
           trial_queries_remaining: max(0, user.trial_queries_limit - user.trial_queries_used)
         }}

      customer_id ->
        case Subscription.list(%{customer: customer_id, status: "active"}) do
          {:ok, %{data: []}} ->
            # No active subscription
            {:ok,
             %{
               active: false,
               trial_queries_remaining: max(0, user.trial_queries_limit - user.trial_queries_used)
             }}

          {:ok, %{data: [subscription | _]}} ->
            # Active subscription found
            # Get the price details from the subscription
            price = hd(subscription.items.data).price
            
            {:ok,
             %{
               active: true,
               subscription_id: subscription.id,
               current_period_end: subscription.current_period_end,
               cancel_at_period_end: subscription.cancel_at_period_end,
               # Add pricing details
               interval: price.recurring.interval,
               interval_count: price.recurring.interval_count,
               amount: price.unit_amount,
               currency: price.currency
             }}

          error ->
            error
        end
    end
  end

  @doc """
  Handles webhook events from Stripe
  """
  def handle_webhook_event(event) do
    # Handle both Stripe event objects and raw JSON maps
    event_type = if is_map(event) && is_binary(event["type"]), do: event["type"], else: event.type

    event_data =
      if is_map(event) && event["data"], do: event["data"]["object"], else: event.data.object

    Logger.info("Handling webhook event: #{event_type}")

    case event_type do
      "checkout.session.completed" ->
        session_id = if is_map(event_data), do: event_data["id"], else: event_data.id
        Logger.info("Processing checkout.session.completed for session: #{session_id}")
        handle_checkout_completed(event_data)

      "customer.subscription.created" ->
        # Handle new subscription creation (important for resubscribe flow)
        Logger.info("Processing customer.subscription.created")
        handle_subscription_updated(event_data)

      "customer.subscription.updated" ->
        handle_subscription_updated(event_data)

      "customer.subscription.deleted" ->
        handle_subscription_deleted(event_data)

      _ ->
        # Ignore other events
        Logger.info("Ignoring webhook event type: #{event_type}")
        :ok
    end
  end

  # Private functions

  defp create_session(customer_id, email, price_type, success_url, cancel_url) do
    price_id =
      case price_type do
        "yearly" -> yearly_price_id()
        _ -> monthly_price_id()
      end

    Logger.info(
      "Creating Stripe session - customer: #{customer_id}, price_id: #{price_id}, price_type: #{price_type}"
    )

    # All prices are subscription mode
    mode = "subscription"

    session_params = %{
      customer: customer_id,
      mode: mode,
      line_items: [
        %{
          price: price_id,
          quantity: 1
        }
      ],
      success_url: success_url,
      cancel_url: cancel_url,
      allow_promotion_codes: true,
      billing_address_collection: "auto"
    }

    # If user doesn't have email, enable customer update to collect it
    session_params =
      if is_nil(email) do
        Map.put(session_params, :customer_update, %{
          address: "auto",
          name: "auto"
        })
      else
        session_params
      end

    Session.create(session_params)
  end

  defp create_session_with_price_id(customer_id, email, price_id, success_url, cancel_url) do
    Logger.info("Creating Stripe session - customer: #{customer_id}, price_id: #{price_id}")

    # First fetch the price to determine if it's one-time or recurring
    case Stripe.Price.retrieve(price_id) do
      {:ok, price} ->
        # Determine payment mode based on price type
        mode = if price.type == "one_time", do: "payment", else: "subscription"

        session_params = %{
          customer: customer_id,
          mode: mode,
          line_items: [
            %{
              price: price_id,
              quantity: 1
            }
          ],
          success_url: success_url,
          cancel_url: cancel_url,
          allow_promotion_codes: true,
          billing_address_collection: "auto"
        }

        # If user doesn't have email, enable customer update to collect it
        session_params =
          if is_nil(email) do
            Map.put(session_params, :customer_update, %{
              address: "auto",
              name: "auto"
            })
          else
            session_params
          end

        Session.create(session_params)

      {:error, _} = error ->
        error
    end
  end

  defp handle_checkout_completed(session) do
    # Handle both Stripe objects and plain maps
    customer_id =
      if is_map(session) && session["customer"], do: session["customer"], else: session.customer

    mode = if is_map(session) && session["mode"], do: session["mode"], else: session.mode

    amount_total =
      if is_map(session) && session["amount_total"],
        do: session["amount_total"],
        else: session.amount_total

    session_id = if is_map(session) && session["id"], do: session["id"], else: session.id

    Logger.info("Processing checkout completed for customer: #{customer_id}")
    Logger.info("Session mode: #{mode}, amount_total: #{amount_total}")

    # Retrieve the customer
    with {:ok, customer} <- Customer.retrieve(customer_id),
         user when not is_nil(user) <- Accounts.get_user_by_stripe_customer_id(customer.id) do
      Logger.info("Found user #{user.id} for customer #{customer.id}")

      # Prepare updates
      updates = %{}

      # Update email if it was collected during checkout
      updates =
        if is_nil(user.email) && not is_nil(customer.email) do
          Map.put(updates, :email, customer.email)
        else
          updates
        end

      # Set subscription status for subscription checkouts
      updates =
        if mode == "subscription" do
          Logger.info("This is a subscription checkout")
          # For subscriptions, we'll get the details via subscription webhook
          # But we can set initial status
          Map.put(updates, :subscription_status, "active")
        else
          updates
        end

      # Apply updates if any
      if map_size(updates) > 0 do
        Logger.info("Updating user with: #{inspect(updates)}")

        case Accounts.update_user(user, updates) do
          {:ok, updated_user} ->
            Logger.info("Successfully updated user #{updated_user.id}")

          {:error, error} ->
            Logger.error("Failed to update user: #{inspect(error)}")
        end
      end
    else
      error ->
        Logger.error("Failed to process checkout: #{inspect(error)}")
    end

    :ok
  end

  # Helper function to extract current_period_end from subscription data
  defp get_subscription_period_end(subscription) when is_map(subscription) do
    cond do
      # First check top level
      subscription["current_period_end"] ->
        subscription["current_period_end"]

      # Then check in items.data[0] for incomplete subscriptions
      get_in(subscription, ["items", "data"]) ->
        case get_in(subscription, ["items", "data"]) do
          [first_item | _] -> first_item["current_period_end"]
          _ -> nil
        end

      # For Stripe objects (not plain maps)
      true ->
        try do
          subscription.current_period_end
        rescue
          _ -> nil
        end
    end
  end

  defp get_subscription_period_end(subscription) do
    # For Stripe objects
    try do
      subscription.current_period_end
    rescue
      _ -> nil
    end
  end

  defp handle_subscription_updated(subscription) do
    # Handle both Stripe objects and plain maps
    customer_id =
      if is_map(subscription) && subscription["customer"],
        do: subscription["customer"],
        else: subscription.customer

    subscription_id =
      if is_map(subscription) && subscription["id"], do: subscription["id"], else: subscription.id

    status =
      if is_map(subscription) && subscription["status"],
        do: subscription["status"],
        else: subscription.status

    Logger.info(
      "Processing subscription updated for customer: #{customer_id}, subscription: #{subscription_id}, status: #{status}"
    )

    # Find user by Stripe customer ID
    case Accounts.get_user_by_stripe_customer_id(customer_id) do
      nil ->
        Logger.error("User not found for customer: #{customer_id}")
        {:error, "User not found"}

      user ->
        # Base updates - normalize status strings
        new_subscription_status = case status do
          "active" -> "active"
          "trialing" -> "active"  # Treat trialing as active
          "canceled" -> "canceled"
          "past_due" -> "past_due"
          "incomplete" -> "incomplete"
          _ -> "canceled"  # Default fallback
        end
        
        # Prevent downgrading from active/canceled to incomplete
        # This handles race conditions where webhooks arrive out of order
        current_status = user.subscription_status
        
        should_update_status = cond do
          # If we're trying to set to incomplete but already have a final status, skip
          new_subscription_status == "incomplete" && current_status in ["active", "canceled", "lifetime"] ->
            Logger.warning("Skipping status downgrade from #{current_status} to incomplete for subscription #{subscription_id}")
            false
            
          # Otherwise allow the update
          true ->
            true
        end
        
        updates = if should_update_status do
          %{
            subscription_id: subscription_id,
            subscription_status: new_subscription_status
          }
        else
          %{subscription_id: subscription_id}
        end

        # Add current_period_end if available
        current_period_end = get_subscription_period_end(subscription)

        updates =
          if current_period_end do
            Map.put(
              updates,
              :subscription_current_period_end,
              DateTime.from_unix!(current_period_end)
            )
          else
            updates
          end

        case Accounts.update_user(user, updates) do
          {:ok, _updated_user} ->
            Logger.info("Updated subscription status for user #{user.id}: #{status}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to update subscription status: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp handle_subscription_deleted(subscription) do
    # Handle both Stripe objects and plain maps
    customer_id =
      if is_map(subscription) && subscription["customer"],
        do: subscription["customer"],
        else: subscription.customer

    subscription_id =
      if is_map(subscription) && subscription["id"], do: subscription["id"], else: subscription.id

    Logger.info(
      "Processing subscription deleted for customer: #{customer_id}, subscription: #{subscription_id}"
    )

    # Subscription cancelled - user goes back to trial limits
    case Accounts.get_user_by_stripe_customer_id(customer_id) do
      nil ->
        Logger.error("User not found for customer: #{customer_id}")
        {:error, "User not found"}

      user ->
        # Clear subscription status
        updates = %{
          subscription_status: "canceled",
          subscription_current_period_end: nil
          # Keep subscription_id for historical reference
        }

        case Accounts.update_user(user, updates) do
          {:ok, _updated_user} ->
            Logger.info("Cleared subscription status for user #{user.id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to clear subscription status: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Fetches available pricing options for a specific user
  Returns only the price IDs that should be shown to this user
  """
  def get_available_prices_for_user(user) do
    # Determine which price IDs to show this user
    allowed_price_ids = get_allowed_price_ids(user)

    # Fetch all active prices from Stripe
    case Stripe.Price.list(%{active: true, expand: ["data.product"]}) do
      {:ok, %{data: prices}} ->
        # Filter to only allowed prices
        available_prices =
          prices
          |> Enum.filter(&(&1.id in allowed_price_ids))
          |> Enum.map(&format_price_for_display/1)

        {:ok,
         %{
           prices: available_prices,
           trial: %{
             queries_limit: user.trial_queries_limit,
             queries_used: user.trial_queries_used,
             queries_remaining: max(0, user.trial_queries_limit - user.trial_queries_used)
           }
         }}

      error ->
        Logger.error("Failed to fetch Stripe prices: #{inspect(error)}")
        error
    end
  end

  defp get_allowed_price_ids(_user) do
    # All users see monthly and yearly pricing
    [monthly_price_id(), yearly_price_id()]
    # Remove any nil values from missing env vars
    |> Enum.filter(&(&1 != nil))
  end

  defp format_price_for_display(price) do
    # Get features for this price
    features = get_features_for_price(price)

    base_data = %{
      price_id: price.id,
      product_id: price.product.id,
      amount: price.unit_amount,
      currency: price.currency,
      # Product info from expanded data
      name: price.product.name || format_price_name(price),
      description: price.product.description,
      metadata: price.product.metadata || %{},
      # Formatted display price
      display_price: format_price_string(price),
      # Add features - ensure it's always an array
      features: features
    }

    # Add recurring fields only if it's a recurring price
    if price.type == "recurring" and price.recurring do
      base_data
      |> Map.put(:interval, price.recurring.interval)
      |> Map.put(:interval_count, price.recurring.interval_count)
    else
      # For one-time prices, indicate it's a one-time payment
      base_data
      |> Map.put(:interval, "one_time")
      |> Map.put(:interval_count, 1)
    end
  end

  defp get_features_for_price(price) do
    # Define features based on price ID or product metadata
    cond do
      # Monthly plan
      price.id == monthly_price_id() ->
        [
          "Unlimited AI-powered replies",
          "Screenshot context capture",
          "Compose and reply to emails, messages, etc",
          "Ask questions about your screen in Ask mode",
          "Chat & Email support"
        ]

      # Yearly plan
      price.id == yearly_price_id() ->
        [
          "Unlimited AI-powered replies",
          "Screenshot context capture",
          "Compose and reply to emails, messages, etc",
          "Ask questions about your screen in Ask mode",
          "Chat & Email support",
          "33% discount vs monthly"
        ]

      # Default features
      true ->
        [
          "AI-powered replies",
          "Core features",
          "Community support"
        ]
    end
  end

  defp format_price_string(price) do
    amount = price.unit_amount / 100
    base = "$#{:erlang.float_to_binary(amount, decimals: 2)}"

    # Check if it's a one-time price (lifetime)
    if price.type == "one_time" do
      "#{base} one-time"
    else
      # Only access recurring fields if it's a recurring price
      if price.recurring do
        interval = price.recurring.interval
        count = price.recurring.interval_count

        case {interval, count} do
          {"month", 1} -> "#{base}/month"
          {"year", 1} -> "#{base}/year"
          {"month", n} -> "#{base} every #{n} months"
          {"year", n} -> "#{base} every #{n} years"
          _ -> base
        end
      else
        base
      end
    end
  end

  defp format_price_name(price) do
    cond do
      price.type == "one_time" -> "Lifetime"
      price.recurring && price.recurring.interval == "month" -> "Monthly"
      price.recurring && price.recurring.interval == "year" -> "Yearly"
      true -> "Plan"
    end
  end
end
