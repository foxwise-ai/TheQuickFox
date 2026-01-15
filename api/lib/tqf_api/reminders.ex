defmodule TqfApi.Reminders do
  @moduledoc """
  Handles reminder creation, calendar invite generation, and email sending.
  """

  require Logger

  @resend_api_url "https://api.resend.com/emails"
  @from_email "TheQuickFox <noreply@thequickfox.ai>"

  defmodule Reminder do
    @moduledoc """
    Struct representing a reminder.
    """
    defstruct [:email, :remind_at, :token, :created_at]
  end

  @doc """
  Creates a new reminder with a unique token.
  """
  def create_reminder(email, remind_at) do
    # Parse the remind_at datetime
    case DateTime.from_iso8601(remind_at) do
      {:ok, datetime, _offset} ->
        reminder = %Reminder{
          email: email,
          remind_at: datetime,
          token: generate_token(),
          created_at: DateTime.utc_now()
        }

        # Store in ETS for simple in-memory storage
        # In production, you might want to use the database
        :ets.insert(:reminders, {reminder.token, reminder})

        {:ok, reminder}

      {:error, _reason} ->
        {:error, :invalid_datetime}
    end
  end

  @doc """
  Gets a reminder by its token.
  """
  def get_reminder_by_token(token) do
    case :ets.lookup(:reminders, token) do
      [{^token, reminder}] -> {:ok, reminder}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Generates an .ics calendar file content for a reminder.
  """
  def generate_ics(%Reminder{remind_at: remind_at}) do
    # Format dates for iCalendar (YYYYMMDDTHHMMSSZ)
    start_time = format_ics_datetime(remind_at)
    end_time = format_ics_datetime(DateTime.add(remind_at, 15 * 60, :second))
    now = format_ics_datetime(DateTime.utc_now())
    uid = "reminder-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}@thequickfox.ai"

    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//TheQuickFox//Reminder//EN
    CALSCALE:GREGORIAN
    METHOD:PUBLISH
    BEGIN:VEVENT
    UID:#{uid}
    DTSTAMP:#{now}
    DTSTART:#{start_time}
    DTEND:#{end_time}
    SUMMARY:Install TheQuickFox
    DESCRIPTION:Time to install TheQuickFox on your Mac!\\n\\nDownload: https://download.thequickfox.ai/releases/TheQuickFox-latest.dmg\\n\\nTheQuickFox is your AI writing companion that works in any app. Press Control+Control and get instant help with emails\\, messages\\, and more.
    URL:https://www.thequickfox.ai
    STATUS:CONFIRMED
    BEGIN:VALARM
    ACTION:DISPLAY
    DESCRIPTION:Install TheQuickFox
    TRIGGER:-PT10M
    END:VALARM
    END:VEVENT
    END:VCALENDAR
    """
    |> String.trim()
  end

  @doc """
  Sends an email with the calendar invite attached.
  """
  def send_calendar_email(%Reminder{email: email} = reminder) do
    ics_content = generate_ics(reminder)
    ics_base64 = Base.encode64(ics_content)

    body = %{
      from: @from_email,
      to: [email],
      subject: "Reminder: Install TheQuickFox on your Mac",
      html: calendar_email_html(reminder),
      text: calendar_email_text(reminder),
      attachments: [
        %{
          filename: "thequickfox-reminder.ics",
          content: ics_base64,
          type: "text/calendar"
        }
      ]
    }

    case send_email(body) do
      {:ok, response} ->
        Logger.info("Calendar invite email sent to #{email}")
        {:ok, response}

      {:error, reason} = error ->
        Logger.error("Failed to send calendar email to #{email}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

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

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp format_ics_datetime(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp calendar_email_html(%Reminder{remind_at: remind_at}) do
    formatted_time = Calendar.strftime(remind_at, "%B %d, %Y at %I:%M %p UTC")

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Reminder: Install TheQuickFox</title>
    </head>
    <body style="font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #1a202c; max-width: 500px; margin: 0 auto; padding: 40px 20px; background: #f8fafc;">
      <div style="background: #fff; border-radius: 16px; padding: 40px; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.06); border: 1px solid #e2e8f0;">
        <div style="text-align: center; margin-bottom: 32px;">
          <img src="https://www.thequickfox.ai/tqf_128x128.png" alt="TheQuickFox" style="width: 64px; height: 64px; margin-bottom: 16px;">
          <h1 style="color: #1a202c; margin: 0; font-size: 24px; font-weight: 700;">Your Reminder is Set!</h1>
        </div>

        <p style="color: #64748b; font-size: 15px; margin-bottom: 20px; text-align: center;">
          You asked us to remind you to install TheQuickFox at:
        </p>

        <div style="background: linear-gradient(135deg, #3182CE 0%, #0ea5e9 100%); color: white; padding: 16px 24px; border-radius: 12px; text-align: center; margin-bottom: 24px;">
          <strong style="font-size: 18px;">#{formatted_time}</strong>
        </div>

        <p style="color: #64748b; font-size: 15px; margin-bottom: 28px; text-align: center;">
          We've attached a calendar invite to this email. Add it to your calendar so you don't forget!
        </p>

        <div style="text-align: center; margin-bottom: 28px;">
          <a href="https://download.thequickfox.ai/releases/TheQuickFox-latest.dmg" style="display: inline-block; background: linear-gradient(135deg, #059669 0%, #10B981 100%); color: white; text-decoration: none; padding: 14px 36px; border-radius: 10px; font-weight: 600; font-size: 15px;">
            Download Now
          </a>
        </div>

        <p style="color: #94a3b8; font-size: 13px; text-align: center; margin: 0;">
          Can't wait? Download now and start writing with AI in any app.
        </p>
      </div>

      <p style="color: #94a3b8; font-size: 12px; text-align: center; margin-top: 24px;">
        TheQuickFox &mdash; Your AI companion with zero context switch
      </p>
    </body>
    </html>
    """
  end

  defp calendar_email_text(%Reminder{remind_at: remind_at}) do
    formatted_time = Calendar.strftime(remind_at, "%B %d, %Y at %I:%M %p UTC")

    """
    Your Reminder is Set!

    You asked us to remind you to install TheQuickFox at:
    #{formatted_time}

    We've attached a calendar invite to this email. Add it to your calendar so you don't forget!

    Download TheQuickFox: https://download.thequickfox.ai/releases/TheQuickFox-latest.dmg

    --
    TheQuickFox - Your AI companion with zero context switch
    """
  end
end
