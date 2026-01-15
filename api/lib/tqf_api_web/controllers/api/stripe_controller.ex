defmodule TqfApiWeb.Api.StripeController do
  use TqfApiWeb, :controller
  require Logger

  alias TqfApi.Billing.StripeService
  alias TqfApi.Repo

  action_fallback(TqfApiWeb.FallbackController)

  def create_checkout_session(conn, %{"price_id" => price_id}) do
    device = conn.assigns.current_device
    user = device.user

    # Generate success and cancel URLs using endpoint configuration
    base_url = TqfApiWeb.Endpoint.url()

    success_url = "#{base_url}/checkout/success?session_id={CHECKOUT_SESSION_ID}"
    cancel_url = "#{base_url}/checkout/cancel"

    case StripeService.create_checkout_session_with_price_id(
           user,
           price_id,
           success_url,
           cancel_url
         ) do
      {:ok, session} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            checkout_url: session.url,
            session_id: session.id
          }
        })

      {:error, %Stripe.Error{} = error} ->
        require Logger
        Logger.error("Stripe error: #{inspect(error)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Stripe error",
          details: error.message || inspect(error)
        })

      {:error, reason} ->
        require Logger
        Logger.error("Checkout session error: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create checkout session", details: inspect(reason)})
    end
  end

  def webhook(conn, params) do
    payload = conn.assigns[:raw_body]
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    endpoint_secret = System.get_env("STRIPE_WEBHOOK_SECRET")

    require Logger

    # TEMPORARY: Bypass signature verification for testing
    # TODO: Remove this once webhook secret is properly configured
    bypass_verification = false

    event =
      if bypass_verification do
        Logger.warning("⚠️  BYPASSING webhook signature verification - TEMPORARY FOR TESTING")
        # The params already contain the parsed JSON
        {:ok, params}
      else
        # Production: verify signature
        Stripe.Webhook.construct_event(payload, signature, endpoint_secret)
      end

    case event do
      {:ok, event_data} ->
        Logger.info("Webhook received: #{event_data["type"]}")

        # Handle the event asynchronously
        Task.start(fn ->
          StripeService.handle_webhook_event(event_data)
        end)

        conn
        |> put_status(:ok)
        |> json(%{received: true})

      {:error, reason} ->
        Logger.error("Webhook error: #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid webhook", details: inspect(reason)})
    end
  end

  def customer_portal(conn, _params) do
    device = conn.assigns.current_device
    user = device.user

    Logger.info(
      "Customer portal request for user #{user.id}, stripe_customer_id: #{inspect(user.stripe_customer_id)}"
    )

    cond do
      is_nil(user.stripe_customer_id) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No Stripe customer ID found for this user"})

      !TqfApi.Accounts.User.has_active_subscription?(user) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active subscription found"})

      true ->
        return_url = TqfApiWeb.Endpoint.url()

        case Stripe.BillingPortal.Session.create(%{
               customer: user.stripe_customer_id,
               return_url: return_url
             }) do
          {:ok, session} ->
            conn
            |> put_status(:ok)
            |> json(%{
              data: %{
                portal_url: session.url
              }
            })

          {:error, reason} ->
            Logger.error("Failed to create portal session: #{inspect(reason)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to create portal session", details: inspect(reason)})
        end
    end
  end

  def pricing(conn, _params) do
    device = conn.assigns.current_device
    user = device.user

    case StripeService.get_available_prices_for_user(user) do
      {:ok, pricing_data} ->
        conn
        |> put_status(:ok)
        |> json(%{data: pricing_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Failed to fetch pricing", details: inspect(reason)})
    end
  end
end
