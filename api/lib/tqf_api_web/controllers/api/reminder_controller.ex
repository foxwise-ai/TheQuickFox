defmodule TqfApiWeb.Api.ReminderController do
  use TqfApiWeb, :controller

  alias TqfApi.Reminders

  require Logger

  @doc """
  Creates a reminder and sends a calendar invite email.
  """
  def create(conn, %{"email" => email, "remind_at" => remind_at}) do
    case Reminders.create_reminder(email, remind_at) do
      {:ok, reminder} ->
        # Send email with calendar invite asynchronously
        Task.start(fn ->
          Reminders.send_calendar_email(reminder)
        end)

        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          ics_url: "/api/v1/reminders/calendar.ics?token=#{reminder.token}"
        })

      {:error, reason} ->
        Logger.error("Failed to create reminder: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create reminder"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: email, remind_at"})
  end

  @doc """
  Downloads the .ics calendar file.
  """
  def download_ics(conn, %{"token" => token}) do
    case Reminders.get_reminder_by_token(token) do
      {:ok, reminder} ->
        ics_content = Reminders.generate_ics(reminder)

        conn
        |> put_resp_content_type("text/calendar")
        |> put_resp_header("content-disposition", "attachment; filename=\"thequickfox-reminder.ics\"")
        |> send_resp(200, ics_content)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Reminder not found"})
    end
  end

  def download_ics(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing token parameter"})
  end
end
