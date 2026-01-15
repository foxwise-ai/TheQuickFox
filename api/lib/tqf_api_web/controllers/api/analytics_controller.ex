defmodule TqfApiWeb.Api.AnalyticsController do
  use TqfApiWeb, :controller

  alias TqfApi.Analytics

  action_fallback(TqfApiWeb.FallbackController)

  @doc """
  Get comprehensive analytics metrics for the authenticated user.

  Accepts query params:
  - time_range: "7d", "30d", or "all" (defaults to "30d")
  """
  def metrics(conn, params) do
    device = conn.assigns.current_device
    time_range = params["time_range"] || "30d"

    metrics = Analytics.get_metrics(device.user_id, time_range)

    conn
    |> json(%{
      data: metrics
    })
  end
end
