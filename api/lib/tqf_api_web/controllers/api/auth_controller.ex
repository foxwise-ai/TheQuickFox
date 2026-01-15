defmodule TqfApiWeb.Api.AuthController do
  use TqfApiWeb, :controller

  alias TqfApi.Auth
  alias TqfApi.Mailer

  action_fallback(TqfApiWeb.FallbackController)

  @doc """
  Initiates email verification for browser extension registration.
  Creates a verification record and sends a magic link email.
  Returns the verification ID for the client to subscribe to updates.
  """
  def register(conn, %{"email" => email}) do
    case Auth.create_email_verification(email) do
      {:ok, verification} ->
        # Send verification email
        case Mailer.send_verification_email(email, verification.verification_token) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{
              data: %{
                # Return socket_token as verification_id so the client joins the correct channel
                verification_id: verification.socket_token,
                message: "Verification email sent. Check your inbox."
              }
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to send verification email", details: inspect(reason)})
        end

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid email", details: format_errors(changeset)})
    end
  end

  @doc """
  Verifies an email via the magic link token.
  Creates/finds user, creates device with auth token, and broadcasts to channel.
  Redirects to success page.
  """
  def verify(conn, %{"token" => token}) do
    case Auth.verify_email(token) do
      {:ok, %{verification: verification, user: _user, device: device}} ->
        # Broadcast to Phoenix channel that verification is complete
        TqfApiWeb.Endpoint.broadcast(
          "verification:#{verification.socket_token}",
          "verified",
          %{auth_token: device.auth_token}
        )

        # Redirect to success page
        success_url = get_success_url()
        redirect(conn, external: success_url)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid verification link"})

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "Verification link has expired. Please request a new one."})

      {:error, :already_verified} ->
        # Still redirect to success page if already verified
        success_url = get_success_url()
        redirect(conn, external: success_url)
    end
  end

  @doc """
  Returns the current status of a verification.
  Used for polling if websocket is unavailable.
  """
  def status(conn, %{"id" => id}) do
    try do
      verification = Auth.get_verification!(id)

      conn
      |> put_status(:ok)
      |> json(%{
        data: %{
          status: verification.status,
          verified_at: verification.verified_at
        }
      })
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Verification not found"})
    end
  end

  defp get_success_url do
    "#{TqfApiWeb.Endpoint.url()}/extension/verified"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
