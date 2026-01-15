defmodule TqfApi.Auth do
  @moduledoc """
  The Auth context for email verification and authentication.
  """

  import Ecto.Query, warn: false
  alias TqfApi.Repo
  alias TqfApi.Auth.EmailVerification
  alias TqfApi.Accounts
  alias TqfApi.Accounts.User

  # Verification tokens expire after 15 minutes
  @token_expiry_minutes 60

  @doc """
  Creates a new email verification record and returns it.
  Generates a unique token for the magic link.
  """
  def create_email_verification(email) do
    token = generate_verification_token()
    socket_token = generate_socket_token()
    expires_at = DateTime.add(DateTime.utc_now(), @token_expiry_minutes * 60, :second)

    %EmailVerification{}
    |> EmailVerification.changeset(%{
      email: email,
      verification_token: token,
      socket_token: socket_token,
      expires_at: expires_at,
      status: "pending"
    })
    |> Repo.insert()
  end

  @doc """
  Gets an email verification by its token.
  """
  def get_verification_by_token(token) do
    Repo.get_by(EmailVerification, verification_token: token)
  end

  @doc """
  Gets an email verification by ID.
  """
  def get_verification!(id) do
    Repo.get!(EmailVerification, id)
  end

  @doc """
  Verifies an email verification token.
  Creates or finds the user, creates a device with auth token, and returns the result.
  """
  def verify_email(token) do
    case get_verification_by_token(token) do
      nil ->
        {:error, :not_found}

      verification ->
        cond do
          EmailVerification.expired?(verification) ->
            # Mark as expired
            verification
            |> EmailVerification.changeset(%{status: "expired"})
            |> Repo.update()

            {:error, :expired}

          EmailVerification.verified?(verification) ->
            {:error, :already_verified}

          true ->
            # Find or create user by email
            user = find_or_create_user_by_email(verification.email)

            # Create device with auth token for browser extension
            device_uuid = "browser_ext_#{:crypto.strong_rand_bytes(16) |> Base.url_encode64()}"
            auth_token = generate_auth_token()

            {:ok, device} =
              Accounts.create_device(%{
                user_id: user.id,
                device_uuid: device_uuid,
                device_name: "Browser Extension",
                auth_token: auth_token,
                last_seen_at: DateTime.utc_now()
              })

            # Mark verification as verified and associate with user/device
            {:ok, updated_verification} =
              verification
              |> EmailVerification.changeset(%{
                status: "verified",
                verified_at: DateTime.utc_now(),
                user_id: user.id,
                device_id: device.id
              })
              |> Repo.update()

            {:ok, %{verification: updated_verification, user: user, device: device}}
        end
    end
  end

  @doc """
  Finds a user by email or creates a new one.
  """
  def find_or_create_user_by_email(email) do
    case Repo.get_by(User, email: email) do
      nil ->
        {:ok, user} = Accounts.create_user(%{email: email})
        user

      user ->
        user
    end
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  defp generate_verification_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp generate_socket_token do
    Ecto.UUID.generate()
  end

  defp generate_auth_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64()
    |> binary_part(0, 32)
  end
end
