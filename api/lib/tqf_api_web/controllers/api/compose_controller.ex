defmodule TqfApiWeb.Api.ComposeController do
  @moduledoc """
  Handles compose/ask/code requests.
  Client sends mode, query, context - API builds prompt and streams AI response.
  """

  use TqfApiWeb, :controller

  alias TqfApi.Accounts
  alias TqfApi.Prompts

  require Logger

  # API endpoints
  @groq_base_url "https://api.groq.com/openai/v1"
  @gemini_base_url "https://generativelanguage.googleapis.com/v1beta"

  # Models
  @routing_model "llama-3.1-8b-instant"
  @compose_model "moonshotai/kimi-k2-instruct-0905"
  @ask_model "gemini-2.5-flash"

  # Rate limiting for public endpoint
  @ip_limit 5
  @ip_window_ms :timer.hours(24)

  @doc """
  Public endpoint for browser extension (unauthenticated, rate limited by IP).
  """
  def public_create(conn, params) do
    ip_address = get_client_ip(conn)
    Logger.info("Public compose request from IP: #{ip_address}")

    case Hammer.check_rate("public_compose_ip:#{ip_address}", @ip_window_ms, @ip_limit) do
      {:allow, _count} ->
        # Only allow compose/code modes for public (no ask with vision)
        mode = Map.get(params, "mode", "compose")
        handle_request(conn, params)

      {:deny, limit} ->
        retry_after = div(@ip_window_ms, 1000)

        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{
          error: %{
            message: "Rate limit exceeded. You can make #{limit} requests per 24 hours.",
            type: "rate_limit_exceeded",
            retry_after_seconds: retry_after
          }
        })
    end
  end

  @doc """
  Main endpoint for all modes (compose, ask, code).
  """
  def create(conn, params) do
    device = conn.assigns.current_device
    user = Accounts.get_user!(device.user_id)

    with {:ok, _user} <- check_terms_acceptance(user),
         {:ok, _user} <- check_access(user) do
      handle_request(conn, params)
    else
      {:error, :terms_not_accepted} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: %{message: "Terms of service must be accepted", type: "terms_required"}})

      {:error, :no_access} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: %{message: "Subscription or trial quota required", type: "subscription_required"}
        })
    end
  end

  defp check_terms_acceptance(user) do
    if user.terms_accepted_at, do: {:ok, user}, else: {:error, :terms_not_accepted}
  end

  defp check_access(user) do
    cond do
      TqfApi.Accounts.User.has_active_subscription?(user) -> {:ok, user}
      user.trial_queries_used < user.trial_queries_limit -> {:ok, user}
      true -> {:error, :no_access}
    end
  end

  defp handle_request(conn, params) do
    mode = Map.get(params, "mode", "compose")
    query = Map.get(params, "query", "")
    app_info = Map.get(params, "app_info", %{})
    context_text = Map.get(params, "context_text", "")
    screenshot_base64 = Map.get(params, "screenshot_base64")
    tone = Map.get(params, "tone")

    case mode do
      "ask" ->
        handle_ask_mode(conn, query, app_info, context_text, screenshot_base64, tone)

      _ ->
        # compose and code modes use kimi-k2
        handle_compose_mode(conn, mode, query, app_info, context_text, tone)
    end
  end

  # Ask mode: Route to determine web search vs visual, then use Gemini
  defp handle_ask_mode(conn, query, app_info, context_text, screenshot_base64, tone) do
    app_name = app_info["app_name"]
    window_title = app_info["window_title"]

    # Log screenshot presence
    screenshot_size = if screenshot_base64, do: byte_size(screenshot_base64), else: 0
    Logger.info("Ask mode: screenshot_base64 size=#{screenshot_size} bytes")

    # Route the query
    case route_query(query, app_name, window_title) do
      {:ok, :websearch} ->
        Logger.info("Ask mode: routing to web search")
        stream_gemini_ask(conn, query, app_info, context_text, nil, tone, true)

      {:ok, :visual} ->
        Logger.info("Ask mode: routing to visual analysis")
        stream_gemini_ask(conn, query, app_info, context_text, screenshot_base64, tone, false)

      {:error, reason} ->
        Logger.error("Routing failed: #{inspect(reason)}, defaulting to visual")
        stream_gemini_ask(conn, query, app_info, context_text, screenshot_base64, tone, false)
    end
  end

  # Route query using Groq to determine web search vs visual
  defp route_query(query, app_name, window_title) do
    api_key = System.get_env("GROQ_API_KEY")

    unless api_key do
      {:error, :no_api_key}
    else
      routing_prompt = """
      Analyze this query and determine if it needs:
      1. Web search - for current events, facts, or information lookup
      2. Visual analysis - for questions about what's on screen, UI elements, or design

      Query: "#{query}"
      Context: User is in #{app_name || "unknown app"} with window "#{window_title || "untitled"}"

      Respond with ONLY one word: "websearch" or "visual"
      """

      body =
        Jason.encode!(%{
          "model" => @routing_model,
          "messages" => [%{"role" => "user", "content" => routing_prompt}],
          "max_tokens" => 10
        })

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case HTTPoison.post("#{@groq_base_url}/chat/completions", body, headers,
             recv_timeout: 10_000
           ) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
              decision = content |> String.downcase() |> String.trim()

              if String.contains?(decision, "websearch"),
                do: {:ok, :websearch},
                else: {:ok, :visual}

            _ ->
              {:ok, :visual}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.error("Routing request failed with status #{status}")
          {:ok, :visual}

        {:error, reason} ->
          Logger.error("Routing request error: #{inspect(reason)}")
          {:ok, :visual}
      end
    end
  end

  # Compose/Code mode: Use kimi-k2 via Groq
  defp handle_compose_mode(conn, mode, query, app_info, context_text, tone) do
    messages = Prompts.build_messages(mode, query, app_info, context_text, tone: tone)

    ai_params = %{
      "model" => @compose_model,
      "messages" => messages,
      "stream" => true
    }

    api_key = System.get_env("GROQ_API_KEY")

    if api_key do
      stream_openai_compatible(conn, ai_params, "#{@groq_base_url}/chat/completions", api_key)
    else
      Logger.error("GROQ_API_KEY not configured")
      conn |> put_status(500) |> json(%{error: %{message: "AI service not configured"}})
    end
  end

  # Ask mode: Stream from Gemini with optional web search
  defp stream_gemini_ask(
         conn,
         query,
         app_info,
         context_text,
         screenshot_base64,
         tone,
         enable_web_search
       ) do
    api_key = System.get_env("GEMINI_API_KEY")

    unless api_key do
      Logger.error("GEMINI_API_KEY not configured")
      conn |> put_status(500) |> json(%{error: %{message: "AI service not configured"}})
    else
      # Build messages
      messages =
        if screenshot_base64 && screenshot_base64 != "" && !enable_web_search do
          # Gemini can't do web search + images together
          Prompts.build_messages_with_image(
            "ask",
            query,
            app_info,
            context_text,
            screenshot_base64,
            tone: tone
          )
        else
          Prompts.build_messages("ask", query, app_info, context_text, tone: tone)
        end

      # Convert to Gemini format
      gemini_request = convert_to_gemini_format(messages, enable_web_search)

      url = "#{@gemini_base_url}/models/#{@ask_model}:streamGenerateContent?key=#{api_key}"

      headers = [{"Content-Type", "application/json"}]
      body = Jason.encode!(gemini_request)

      Logger.info("Streaming ask request to Gemini (web_search=#{enable_web_search})")

      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("x-accel-buffering", "no")
        |> send_chunked(200)

      case HTTPoison.post(url, body, headers, stream_to: self(), recv_timeout: :infinity) do
        {:ok, %HTTPoison.AsyncResponse{id: id}} ->
          stream_gemini_response(conn, id, "", false)

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Failed to start Gemini stream: #{inspect(reason)}")

          chunk(
            conn,
            "data: #{Jason.encode!(%{error: %{message: "Failed to connect to AI"}})}\n\n"
          )

          chunk(conn, "data: [DONE]\n\n")
      end

      conn
    end
  end

  # Convert OpenAI messages format to Gemini format
  defp convert_to_gemini_format(messages, enable_web_search) do
    contents =
      Enum.map(messages, fn msg ->
        parts =
          case msg["content"] do
            content when is_binary(content) ->
              [%{text: content}]

            content when is_list(content) ->
              Enum.map(content, fn item ->
                case item["type"] do
                  "text" ->
                    %{text: item["text"]}

                  "image_url" ->
                    image_url = item["image_url"]["url"]

                    if String.starts_with?(image_url, "data:image/") do
                      [_header, base64_data] = String.split(image_url, ",", parts: 2)
                      [mime_part | _] = String.split(image_url, ";")
                      mime_type = String.replace_prefix(mime_part, "data:", "")

                      %{inlineData: %{mimeType: mime_type, data: base64_data}}
                    else
                      nil
                    end

                  _ ->
                    nil
                end
              end)
              |> Enum.reject(&is_nil/1)

            _ ->
              [%{text: ""}]
          end

        %{
          role: if(msg["role"] == "assistant", do: "model", else: "user"),
          parts: parts
        }
      end)

    request = %{contents: contents}

    # Add web search tool if enabled
    if enable_web_search do
      Map.put(request, :tools, [%{google_search: %{}}])
    else
      request
    end
  end

  # Stream Gemini response and convert to OpenAI SSE format
  defp stream_gemini_response(conn, id, error_body, is_error) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} when code >= 200 and code < 300 ->
        stream_gemini_response(conn, id, error_body, false)

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        Logger.error("Gemini API returned error status: #{code}")
        stream_gemini_response(conn, id, error_body, true)

      %HTTPoison.AsyncHeaders{id: ^id} ->
        stream_gemini_response(conn, id, error_body, is_error)

      %HTTPoison.AsyncChunk{id: ^id, chunk: data} ->
        if is_error do
          stream_gemini_response(conn, id, error_body <> data, true)
        else
          case convert_gemini_chunk(data) do
            {:ok, openai_chunk} ->
              case chunk(conn, openai_chunk) do
                {:ok, conn} -> stream_gemini_response(conn, id, error_body, false)
                {:error, _} -> :ok
              end

            :skip ->
              stream_gemini_response(conn, id, error_body, false)
          end
        end

      %HTTPoison.AsyncEnd{id: ^id} ->
        if is_error do
          Logger.error("Gemini API error: #{error_body}")
          chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Gemini API error"}})}\n\n")
        end

        chunk(conn, "data: [DONE]\n\n")
        :ok

      %HTTPoison.Error{id: ^id, reason: reason} ->
        Logger.error("Gemini stream error: #{inspect(reason)}")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Stream error"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    after
      120_000 ->
        Logger.error("Gemini stream timeout")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Stream timeout"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    end
  end

  # Convert Gemini streaming chunk to OpenAI SSE format (with grounding metadata)
  defp convert_gemini_chunk(data) do
    cleaned =
      data
      |> String.trim()
      |> String.trim_leading("[")
      |> String.trim_leading(",")
      |> String.trim_trailing("]")
      |> String.trim()

    if cleaned == "" do
      :skip
    else
      case Jason.decode(cleaned) do
        {:ok, gemini_chunk} ->
          candidate = get_in(gemini_chunk, ["candidates", Access.at(0)])
          text = get_in(candidate, ["content", "parts", Access.at(0), "text"]) || ""
          grounding_metadata = get_in(candidate, ["groundingMetadata"])
          finish_reason = get_in(candidate, ["finishReason"])

          if text != "" or grounding_metadata != nil do
            choice = %{
              index: 0,
              delta: %{content: text},
              finish_reason: if(finish_reason, do: String.downcase(finish_reason), else: nil)
            }

            # Include grounding metadata if present (for citations)
            choice =
              if grounding_metadata do
                Map.put(choice, :grounding_metadata, grounding_metadata)
              else
                choice
              end

            openai_chunk = %{
              id: "gemini-#{System.system_time(:millisecond)}",
              object: "chat.completion.chunk",
              created: System.system_time(:second),
              model: @ask_model,
              choices: [choice]
            }

            {:ok, "data: #{Jason.encode!(openai_chunk)}\n\n"}
          else
            :skip
          end

        {:error, _} ->
          :skip
      end
    end
  end

  # Stream from OpenAI-compatible API (Groq/OpenAI)
  defp stream_openai_compatible(conn, params, url, api_key) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    body = Jason.encode!(params)

    Logger.info("Streaming compose request to #{url}")

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    case HTTPoison.post(url, body, headers, stream_to: self(), recv_timeout: :infinity) do
      {:ok, %HTTPoison.AsyncResponse{id: id}} ->
        stream_openai_response(conn, id, "", false)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to start streaming: #{inspect(reason)}")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Failed to connect to AI"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    end

    conn
  end

  # Stream OpenAI-compatible response (passthrough)
  defp stream_openai_response(conn, id, error_body, is_error) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} when code >= 200 and code < 300 ->
        stream_openai_response(conn, id, error_body, false)

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        Logger.error("AI API returned error status: #{code}")
        stream_openai_response(conn, id, error_body, true)

      %HTTPoison.AsyncHeaders{id: ^id} ->
        stream_openai_response(conn, id, error_body, is_error)

      %HTTPoison.AsyncChunk{id: ^id, chunk: data} ->
        if is_error do
          stream_openai_response(conn, id, error_body <> data, true)
        else
          case chunk(conn, data) do
            {:ok, conn} -> stream_openai_response(conn, id, error_body, false)
            {:error, _} -> :ok
          end
        end

      %HTTPoison.AsyncEnd{id: ^id} ->
        if is_error do
          Logger.error("AI API error: #{error_body}")
          chunk(conn, "data: #{Jason.encode!(%{error: %{message: "AI API error"}})}\n\n")
          chunk(conn, "data: [DONE]\n\n")
        end

        :ok

      %HTTPoison.Error{id: ^id, reason: reason} ->
        Logger.error("Stream error: #{inspect(reason)}")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Stream error"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    after
      120_000 ->
        Logger.error("Stream timeout")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Stream timeout"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    end
  end

  defp get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
