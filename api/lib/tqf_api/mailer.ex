defmodule TqfApi.Mailer do
  @moduledoc """
  Email sending via Resend API.
  """

  require Logger

  @resend_api_url "https://api.resend.com/emails"
  @from_email "TheQuickFox <noreply@thequickfox.ai>"

  @doc """
  Sends a verification email with a magic link.
  """
  def send_verification_email(to_email, token) do
    verify_url = get_verify_url(token)

    body = %{
      from: @from_email,
      to: [to_email],
      subject: "Verify your email for TheQuickFox",
      html: verification_email_html(verify_url),
      text: verification_email_text(verify_url)
    }

    case send_email(body) do
      {:ok, response} ->
        Logger.info("Verification email sent to #{to_email}")
        {:ok, response}

      {:error, reason} = error ->
        Logger.error("Failed to send verification email to #{to_email}: #{inspect(reason)}")
        error
    end
  end

  defp send_email(body) do
    api_key = get_api_key()

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(@resend_api_url, Jason.encode!(body), headers) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}}
      when status in 200..299 ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, %{status: status, body: response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp get_api_key do
    System.get_env("RESEND_API_KEY") ||
      Application.get_env(:tqf_api, :resend_api_key) ||
      raise "RESEND_API_KEY not configured"
  end

  defp get_verify_url(token) do
    base_url = get_base_url()
    "#{base_url}/api/v1/auth/verify/#{token}"
  end

  defp get_base_url do
    TqfApiWeb.Endpoint.url()
  end

  defp verification_email_html(verify_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Verify your email</title>
    </head>
    <body style="font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #09213F; max-width: 500px; margin: 0 auto; padding: 40px 20px; background: #FFF9F5;">
      <div style="background: #fff; border-radius: 16px; padding: 40px; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.06); border: 1px solid #E9EDF3;">
        <div style="text-align: center; margin-bottom: 32px;">
          <img src="https://www.thequickfox.ai/images/fox-icon.png" alt="TheQuickFox" style="width: 56px; height: 56px; margin-bottom: 16px;">
          <h1 style="color: #09213F; margin: 0; font-size: 24px; font-weight: 700;">Verify your email</h1>
        </div>

        <p style="color: #475569; font-size: 15px; margin-bottom: 28px; text-align: center;">
          Click the button below to activate TheQuickFox and start writing with AI.
        </p>

        <div style="text-align: center; margin-bottom: 28px;">
          <a href="#{verify_url}" style="display: inline-block; background: linear-gradient(135deg, #FF7A00 0%, #FFC94C 100%); color: white; text-decoration: none; padding: 14px 36px; border-radius: 10px; font-weight: 600; font-size: 15px;">
            Verify Email
          </a>
        </div>

        <p style="color: #94a3b8; font-size: 13px; text-align: center; margin: 0;">
          Link expires in 1 hour. If you didn't request this, ignore this email.
        </p>
      </div>

      <p style="color: #94a3b8; font-size: 12px; text-align: center; margin-top: 24px;">
        TheQuickFox &mdash; AI-powered writing for any text field
      </p>
    </body>
    </html>
    """
  end

  defp verification_email_text(verify_url) do
    """
    Verify your email for TheQuickFox

    Click the link below to activate TheQuickFox and start writing with AI:

    #{verify_url}

    Link expires in 1 hour. If you didn't request this, ignore this email.

    --
    TheQuickFox - AI-powered writing for any text field
    """
  end
end
