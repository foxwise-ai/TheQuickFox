defmodule TqfApiWeb.Router do
  use TqfApiWeb, :router
  # comment to just cause gh aciton build :roll my eyes:

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :public_api do
    plug(:accepts, ["json"])

    plug(CORSPlug, origin: &TqfApiWeb.Router.cors_origin/0)
  end

  # CORS origin function - allows regex patterns that can't be used directly in pipeline macro
  def cors_origin do
    [
      "https://www.thequickfox.ai",
      ~r/http:\/\/localhost:\d{4}/,
      ~r/chrome-extension:\/\/.*/
    ]
  end

  pipeline :authenticated do
    plug(TqfApiWeb.Plugs.Auth)
  end

  pipeline :internal do
    plug(:accepts, ["json"])
    plug(TqfApiWeb.Plugs.InternalAuth)
  end

  pipeline :webhook do
    plug(:accepts, ["json"])
    plug(TqfApiWeb.Plugs.RawBody)
  end

  scope "/api/v1", TqfApiWeb.Api, as: :api do
    pipe_through(:api)

    # Public endpoints
    post("/devices/register", DeviceController, :register)
    get("/appcast.xml", AppcastController, :index)
    get("/releases/:filename", DownloadController, :release)

    # Public proxy endpoint with CORS (rate-limited, no auth required)
    scope "/proxy/public" do
      pipe_through(:public_api)

      # Catch OPTIONS requests for CORS preflight
      match(:options, "/*path", ProxyController, :cors_preflight)

      post("/chat/completions", ProxyController, :public_chat_completions)
    end

    # Email verification for browser extension (public with CORS)
    scope "/auth" do
      pipe_through(:public_api)

      match(:options, "/*path", ProxyController, :cors_preflight)

      post("/register", AuthController, :register)
      get("/verify/:token", AuthController, :verify)
      get("/status/:id", AuthController, :status)
    end

    # Public compose endpoint for browser extension (rate limited by IP)
    scope "/public" do
      pipe_through(:public_api)

      match(:options, "/*path", ProxyController, :cors_preflight)

      post("/compose", ComposeController, :public_create)
    end

    # Public reminders endpoint (for mobile landing page)
    scope "/reminders" do
      pipe_through(:public_api)

      match(:options, "/*path", ProxyController, :cors_preflight)

      post("/", ReminderController, :create)
      get("/calendar.ics", ReminderController, :download_ics)
    end

    # Protected endpoints
    scope "/" do
      pipe_through([:public_api, :authenticated])

      # CORS preflight for all protected endpoints
      match(:options, "/*path", ProxyController, :cors_preflight)

      post("/users/accept-terms", DeviceController, :accept_terms)

      post("/usage/track", UsageController, :track)
      get("/usage", UsageController, :show)

      # Analytics endpoints
      get("/analytics/metrics", AnalyticsController, :metrics)

      # Stripe endpoints
      get("/pricing", StripeController, :pricing)
      post("/stripe/checkout", StripeController, :create_checkout_session)
      post("/stripe/portal", StripeController, :customer_portal)

      # Compose endpoint - API builds prompts, streams AI response
      post("/compose", ComposeController, :create)

      # Title generation endpoint
      post("/title", TitleController, :create)

      # Feedback endpoints
      post("/feedback", FeedbackController, :create)
      post("/feedback/:feedback_id/logs", FeedbackController, :upload_logs)
    end
  end

  # Internal endpoints (CI/CD, admin)
  scope "/api/v1/internal", TqfApiWeb.Api, as: :internal do
    pipe_through(:internal)

    post("/releases", ReleasesController, :create)
  end

  # Stripe webhook (no auth required)
  scope "/webhooks", TqfApiWeb.Api do
    pipe_through(:webhook)

    post("/stripe", StripeController, :webhook)
  end

  # Checkout pages (no auth required)
  scope "/checkout", TqfApiWeb do
    pipe_through(:api)

    get("/success", CheckoutController, :success)
    get("/cancel", CheckoutController, :cancel)
  end

  # Extension pages (no auth required)
  scope "/extension", TqfApiWeb do
    pipe_through(:api)

    get("/welcome", ExtensionController, :welcome)
    get("/verified", ExtensionController, :verified)
  end
end
