defmodule TqfApiWeb.VerificationChannel do
  use Phoenix.Channel

  @impl true
  def join("verification:" <> verification_id, _params, socket) do
    # Allow joining any verification channel
    # The verification_id is essentially a secret that only the requester knows
    {:ok, assign(socket, :verification_id, verification_id)}
  end

  # Handle incoming messages (none expected for this channel)
  @impl true
  def handle_in(_event, _payload, socket) do
    {:noreply, socket}
  end
end
