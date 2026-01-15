defmodule TqfApiWeb.UserSocket do
  use Phoenix.Socket

  channel "verification:*", TqfApiWeb.VerificationChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # No authentication required for verification socket
    # The channel topic itself (verification:id) acts as the "auth"
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
