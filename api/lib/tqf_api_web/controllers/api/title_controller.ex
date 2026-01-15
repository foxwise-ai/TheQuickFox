defmodule TqfApiWeb.Api.TitleController do
  @moduledoc """
  Generates titles for conversations using AI.
  """

  use TqfApiWeb, :controller

  alias TqfApi.Accounts

  require Logger

  @groq_base_url "https://api.groq.com/openai/v1"
  @model "llama-3.1-8b-instant"

  def create(conn, params) do
    device = conn.assigns.current_device
    user = Accounts.get_user!(device.user_id)

    if user.terms_accepted_at do
      generate_title(conn, params)
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: %{message: "Terms of service must be accepted", type: "terms_required"}})
    end
  end

  defp generate_title(conn, params) do
    prompt = Map.get(params, "prompt", "")
    max_tokens = Map.get(params, "max_tokens", 50)

    api_key = System.get_env("GROQ_API_KEY")

    unless api_key do
      conn |> put_status(500) |> json(%{error: %{message: "AI service not configured"}})
    else
      body = Jason.encode!(%{
        "model" => @model,
        "messages" => [%{"role" => "user", "content" => prompt}],
        "max_tokens" => max_tokens,
        "temperature" => 0.7
      })

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case HTTPoison.post("#{@groq_base_url}/chat/completions", body, headers, recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, response_body)

        {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
          Logger.error("Groq title generation failed: #{status} - #{response_body}")
          conn
          |> put_status(status)
          |> json(%{error: %{message: "AI request failed"}})

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Groq title generation error: #{inspect(reason)}")
          conn
          |> put_status(502)
          |> json(%{error: %{message: "Failed to connect to AI"}})
      end
    end
  end
end
