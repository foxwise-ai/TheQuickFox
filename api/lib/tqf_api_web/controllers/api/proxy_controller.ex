defmodule TqfApiWeb.Api.ProxyController do
  use TqfApiWeb, :controller

  alias TqfApi.Accounts
  alias TqfApi.ScenarioPresets

  require Logger

  # Groq API endpoint
  @groq_base_url "https://api.groq.com/openai/v1"
  # Gemini API endpoint
  @gemini_base_url "https://generativelanguage.googleapis.com/v1beta"

  # Rate limiting configuration
  # Max requests per IP
  @ip_limit 3
  # 24 hours in milliseconds
  @ip_window_ms :timer.hours(24)
  # Max total requests per day
  @global_limit 10_000
  @global_window_ms :timer.hours(24)

  def cors_preflight(conn, _params) do
    # CORS preflight - CORSPlug already added headers via pipeline
    send_resp(conn, 200, "")
  end

  def public_chat_completions(conn, params) do
    # Debug: Log all headers
    # Logger.info("Request headers: #{inspect(conn.req_headers)}")
    Logger.info("Remote IP: #{inspect(conn.remote_ip)}")

    # Get client IP address
    ip_address = get_client_ip(conn)
    Logger.info("Resolved client IP: #{ip_address}")

    # Validate request has required fields and get preset params
    with {:ok, scenario_id} <- Map.fetch(params, "scenario_id"),
         {:ok, message} <- Map.fetch(params, "message"),
         {:ok, ai_params} <-
           ScenarioPresets.get_scenario_params(scenario_id, message, params["context"]) do
      # Override model: use Gemini for image requests, kimi-k2 for text-only
      ai_params =
        if has_image_content?(ai_params) do
          Map.merge(ai_params, %{"model" => "gemini-2.5-flash", "provider" => "gemini"})
        else
          Map.put(ai_params, "model", "moonshotai/kimi-k2-instruct-0905")
        end

      # Check IP-based rate limit
      case Hammer.check_rate("public_ip:#{ip_address}", @ip_window_ms, @ip_limit) do
        {:allow, _count} ->
          # Check global rate limit
          case Hammer.check_rate("public_global", @global_window_ms, @global_limit) do
            {:allow, _count} ->
              proxy_request(conn, ai_params)

            {:deny, _limit} ->
              conn
              |> put_status(:too_many_requests)
              |> json(%{
                error: %{
                  message: "Global rate limit exceeded. Please try again later.",
                  type: "global_rate_limit_exceeded"
                }
              })
          end

        {:deny, limit} ->
          # Calculate retry_after in seconds
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
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: %{
            message: "Missing required fields: scenario_id and message",
            type: "invalid_request"
          }
        })

      {:error, :invalid_scenario} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: %{
            message:
              "Invalid scenario_id. Available scenarios: #{Enum.join(ScenarioPresets.available_scenarios(), ", ")}",
            type: "invalid_scenario"
          }
        })
    end
  end

  def chat_completions(conn, params) do
    device = conn.assigns.current_device
    user = Accounts.get_user!(device.user_id)

    # Check if user has accepted terms of service
    case check_terms_acceptance(user) do
      {:error, :terms_not_accepted} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: %{
            message: "Terms of service must be accepted before using the service",
            type: "terms_required"
          }
        })

      {:ok, user} ->
        # Check if user has active subscription
        if has_proxy_access?(user) do
          proxy_request(conn, params)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: %{
              message: "Proxy access requires an active monthly or yearly subscription",
              type: "subscription_required"
            }
          })
        end
    end
  end

  defp check_terms_acceptance(user) do
    if user.terms_accepted_at do
      {:ok, user}
    else
      {:error, :terms_not_accepted}
    end
  end

  defp has_proxy_access?(user) do
    # Only users with active subscriptions can use the proxy
    # Trial users need remaining quota
    cond do
      TqfApi.Accounts.User.has_active_subscription?(user) ->
        # Active subscribers can use proxy
        true

      true ->
        # Trial users need remaining quota
        user.trial_queries_used < user.trial_queries_limit
    end
  end

  defp get_provider_config(params) do
    # Determine provider based on explicit provider param or model name
    provider = Map.get(params, "provider", "groq")
    model = Map.get(params, "model", "")

    cond do
      provider == "gemini" or String.starts_with?(model, "gemini-") ->
        {:gemini, @gemini_base_url, System.get_env("GEMINI_API_KEY")}

      true ->
        {:groq, @groq_base_url, System.get_env("GROQ_API_KEY")}
    end
  end

  defp proxy_request(conn, params) do
    # Get provider configuration
    {provider_name, base_url, api_key} = get_provider_config(params)

    # Remove provider key from params before sending to AI API
    params = Map.delete(params, "provider")

    if api_key do
      if provider_name == :gemini do
        proxy_gemini_request(conn, params, base_url, api_key)
      else
        proxy_openai_compatible_request(conn, params, provider_name, base_url, api_key)
      end
    else
      Logger.error("API key for #{provider_name} not configured")

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        error: %{
          message: "Proxy service not configured for #{provider_name}",
          type: "configuration_error"
        }
      })
    end
  end

  defp proxy_openai_compatible_request(conn, params, provider_name, base_url, api_key) do
    # Prepare request
    url = "#{base_url}/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(params)

    Logger.info("Proxying request to #{provider_name}: #{url}")
    # IO.inspect(body, label: "Request body")

    case HTTPoison.post(url, body, headers, recv_timeout: 60_000) do
      {:ok,
       %HTTPoison.Response{status_code: status, body: response_body, headers: _response_headers}} ->
        # Log AI API errors for debugging
        if status >= 400 do
          Logger.error("#{provider_name} returned error status: #{status}")
          Logger.error("#{provider_name} error response: #{response_body}")
        end

        # Sanitize response - only return what clients need
        sanitized_response = sanitize_ai_response(response_body)

        conn
        |> put_status(status)
        |> json(sanitized_response)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to proxy #{provider_name} request: #{inspect(reason)}")

        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: %{
            message: "Failed to connect to AI API",
            type: "proxy_error"
          }
        })
    end
  end

  defp proxy_gemini_request(conn, params, base_url, api_key) do
    # Extract model and convert to Gemini format
    model = Map.get(params, "model", "gemini-2.0-flash")

    # Build Gemini URL with API key as query parameter
    url = "#{base_url}/models/#{model}:generateContent?key=#{api_key}"

    headers = [
      {"Content-Type", "application/json"}
    ]

    # Convert OpenAI format to Gemini format
    gemini_params = convert_to_gemini_format(params)
    body = Jason.encode!(gemini_params)

    Logger.info("Proxying request to Gemini: #{url}")
    # IO.inspect(body, label: "Gemini request body")

    case HTTPoison.post(url, body, headers, recv_timeout: 60_000) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        # Log errors for debugging
        if status >= 400 do
          Logger.error("Gemini returned error status: #{status}")
          Logger.error("Gemini error response: #{response_body}")
          # Logger.error("Request body sent to Gemini: #{body}")
        end

        # Convert Gemini response back to OpenAI format
        case Jason.decode(response_body) do
          {:ok, gemini_response} ->
            openai_response = convert_from_gemini_format(gemini_response)

            conn
            |> put_status(status)
            |> json(openai_response)

          {:error, _} ->
            # If we can't decode, pass through as-is
            conn
            |> put_status(status)
            |> text(response_body)
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to proxy Gemini request: #{inspect(reason)}")

        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: %{
            message: "Failed to connect to Gemini API",
            type: "proxy_error"
          }
        })
    end
  end

  # Convert OpenAI chat completion format to Gemini format
  defp convert_to_gemini_format(params) do
    # Extract messages
    messages = Map.get(params, "messages", [])

    # Check if request has web search enabled
    has_web_search = params["web_search_options"] != nil

    # Convert messages to Gemini contents format
    # Handle both simple string content and complex content arrays (for images)
    contents =
      Enum.map(messages, fn msg ->
        parts =
          case msg["content"] do
            content when is_binary(content) ->
              # Simple string content
              [%{text: content}]

            content when is_list(content) ->
              # Array of content items (text + images)
              Enum.map(content, fn item ->
                case item["type"] do
                  "text" ->
                    %{text: item["text"]}

                  "image_url" ->
                    # Only include images if web search is NOT enabled
                    # Gemini API doesn't support both web search and images simultaneously
                    if has_web_search do
                      Logger.warning(
                        "Skipping image in request because web search is enabled - Gemini doesn't support both"
                      )

                      nil
                    else
                      # Extract base64 data from data URL
                      image_url = item["image_url"]["url"]

                      if String.starts_with?(image_url, "data:image/") do
                        # Parse data URL: data:image/png;base64,<data>
                        [_header, base64_data] = String.split(image_url, ",", parts: 2)
                        [mime_part | _] = String.split(image_url, ";")
                        mime_type = String.replace_prefix(mime_part, "data:", "")

                        %{
                          inlineData: %{
                            mimeType: mime_type,
                            data: base64_data
                          }
                        }
                      else
                        nil
                      end
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

    # Build base request
    request = %{
      contents: contents
    }

    # Add generation config if present
    request =
      if params["temperature"] || params["max_tokens"] do
        config = %{}

        config =
          if params["temperature"],
            do: Map.put(config, :temperature, params["temperature"]),
            else: config

        config =
          if params["max_tokens"],
            do: Map.put(config, :maxOutputTokens, params["max_tokens"]),
            else: config

        Map.put(request, :generationConfig, config)
      else
        request
      end

    # Add web search if web_search_options is present
    # Note: Gemini doesn't support web search + images in the same request
    # Gemini uses google_search field, not tools with googleSearchRetrieval
    request =
      if has_web_search do
        Map.put(request, :tools, [
          %{google_search: %{}}
        ])
      else
        request
      end

    request
  end

  # Convert Gemini response to OpenAI format
  defp convert_from_gemini_format(gemini_response) do
    candidate = get_in(gemini_response, ["candidates", Access.at(0)])

    # Extract text from Gemini response
    text = get_in(candidate, ["content", "parts", Access.at(0), "text"]) || ""

    # Extract grounding metadata if present
    grounding_metadata = get_in(candidate, ["groundingMetadata"])
    finish_reason = get_in(candidate, ["finishReason"])

    # Build choice with optional grounding metadata
    choice = %{
      index: 0,
      message: %{
        role: "assistant",
        content: text
      },
      finish_reason: if(finish_reason, do: String.downcase(finish_reason), else: "stop")
    }

    # Add grounding metadata to choice if present
    choice =
      if grounding_metadata do
        Map.put(choice, :grounding_metadata, grounding_metadata)
      else
        choice
      end

    # Build OpenAI-compatible response
    %{
      id: "gemini-#{System.system_time(:millisecond)}",
      object: "chat.completion",
      created: System.system_time(:second),
      model: gemini_response["modelVersion"] || "gemini-2.0-flash",
      choices: [choice]
    }
  end

  def stream_chat_completions(conn, params) do
    device = conn.assigns.current_device
    user = Accounts.get_user!(device.user_id)

    # Check if user has accepted terms of service
    case check_terms_acceptance(user) do
      {:error, :terms_not_accepted} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: %{
            message: "Terms of service must be accepted before using the service",
            type: "terms_required"
          }
        })

      {:ok, user} ->
        if has_proxy_access?(user) do
          proxy_stream_request(conn, params)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: %{
              message: "Proxy access requires an active monthly or yearly subscription",
              type: "subscription_required"
            }
          })
        end
    end
  end

  defp proxy_stream_request(conn, params) do
    # Get provider configuration
    {provider_name, base_url, api_key} = get_provider_config(params)

    # Remove provider key from params before sending to AI API
    params = Map.delete(params, "provider")

    if api_key do
      if provider_name == :gemini do
        proxy_gemini_stream_request(conn, params, base_url, api_key)
      else
        proxy_openai_compatible_stream_request(conn, params, provider_name, base_url, api_key)
      end
    else
      Logger.error("API key for #{provider_name} not configured")

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        error: %{
          message: "Proxy service not configured for #{provider_name}",
          type: "configuration_error"
        }
      })
    end
  end

  defp proxy_openai_compatible_stream_request(conn, params, provider_name, base_url, api_key) do
    url = "#{base_url}/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    # Ensure streaming is enabled
    params = Map.put(params, "stream", true)
    body = Jason.encode!(params)

    Logger.info("Proxying streaming request to #{provider_name}: #{url}")

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    # Start streaming request
    case HTTPoison.post(url, body, headers, stream_to: self(), recv_timeout: :infinity) do
      {:ok, %HTTPoison.AsyncResponse{id: id}} ->
        stream_response(conn, id)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to start streaming proxy for #{provider_name}: #{inspect(reason)}")

        chunk(
          conn,
          "data: #{Jason.encode!(%{error: %{message: "Failed to connect to AI API", type: "proxy_error"}})}\n\n"
        )

        chunk(conn, "data: [DONE]\n\n")
    end

    conn
  end

  defp proxy_gemini_stream_request(conn, params, base_url, api_key) do
    # Extract model
    model = Map.get(params, "model", "gemini-2.0-flash")

    # Build Gemini streaming URL with API key as query parameter
    url = "#{base_url}/models/#{model}:streamGenerateContent?key=#{api_key}"

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    # Convert OpenAI format to Gemini format
    gemini_params = convert_to_gemini_format(params)
    body = Jason.encode!(gemini_params)

    Logger.info("Proxying streaming request to Gemini: #{url}")

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    # Start streaming request
    case HTTPoison.post(url, body, headers, stream_to: self(), recv_timeout: :infinity) do
      {:ok, %HTTPoison.AsyncResponse{id: id}} ->
        stream_gemini_response(conn, id)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to start streaming proxy for Gemini: #{inspect(reason)}")

        chunk(
          conn,
          "data: #{Jason.encode!(%{error: %{message: "Failed to connect to Gemini API", type: "proxy_error"}})}\n\n"
        )

        chunk(conn, "data: [DONE]\n\n")
    end

    conn
  end

  defp stream_gemini_response(conn, id) do
    stream_gemini_response(conn, id, "", false)
  end

  defp stream_gemini_response(conn, id, error_body, is_error) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} when code >= 200 and code < 300 ->
        # Continue streaming
        stream_gemini_response(conn, id, error_body, false)

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        # Error status - will collect error body in chunks
        Logger.error("Gemini API returned error status: #{code}")
        stream_gemini_response(conn, id, error_body, true)

      %HTTPoison.AsyncHeaders{id: ^id} ->
        # Headers received, continue
        stream_gemini_response(conn, id, error_body, is_error)

      %HTTPoison.AsyncChunk{id: ^id, chunk: data} ->
        if is_error do
          # Accumulate error response body for logging
          stream_gemini_response(conn, id, error_body <> data, true)
        else
          # Log raw chunk from Gemini
          Logger.debug("Raw Gemini chunk: #{inspect(data)}")

          # Convert Gemini SSE chunk to OpenAI format and forward
          case convert_gemini_chunk_to_openai(data) do
            {:ok, openai_chunk} ->
              case chunk(conn, openai_chunk) do
                {:ok, conn} ->
                  stream_gemini_response(conn, id, error_body, false)

                {:error, _reason} ->
                  # Client disconnected
                  :ok
              end

            :skip ->
              # Skip this chunk (e.g., array markers, empty lines)
              stream_gemini_response(conn, id, error_body, false)
          end
        end

      %HTTPoison.AsyncEnd{id: ^id} ->
        if is_error do
          # Log the complete error response
          Logger.error("Gemini API error response: #{error_body}")

          chunk(
            conn,
            "data: #{Jason.encode!(%{error: %{message: "Gemini API error"}})}\n\n"
          )
        end

        chunk(conn, "data: [DONE]\n\n")
        :ok

      %HTTPoison.Error{id: ^id, reason: reason} ->
        Logger.error("Stream error: #{inspect(reason)}")

        chunk(
          conn,
          "data: #{Jason.encode!(%{error: %{message: "Stream error", reason: inspect(reason)}})}\n\n"
        )

        chunk(conn, "data: [DONE]\n\n")
    after
      60_000 ->
        # Timeout after 60 seconds
        Logger.error("Stream timeout")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Stream timeout"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    end
  end

  # Convert Gemini streaming chunk to OpenAI format
  defp convert_gemini_chunk_to_openai(data) do
    # Gemini sends raw JSON chunks (not SSE format)
    # Format: "[{...}", ",\r\n{...}", ",\r\n{...}", "]"

    # Clean up the data - remove array markers and leading commas/whitespace
    cleaned =
      data
      |> String.trim()
      |> String.trim_leading("[")
      |> String.trim_leading(",")
      |> String.trim_trailing("]")
      |> String.trim()

    # Skip if it's empty or just whitespace after cleaning
    if cleaned == "" do
      :skip
    else
      case Jason.decode(cleaned) do
        {:ok, gemini_chunk} ->
          Logger.debug("Gemini chunk decoded successfully")

          candidate = get_in(gemini_chunk, ["candidates", Access.at(0)])

          # Extract text from Gemini chunk
          text = get_in(candidate, ["content", "parts", Access.at(0), "text"]) || ""
          Logger.debug("Extracted text: #{inspect(text)}")

          # Extract grounding metadata if present
          grounding_metadata = get_in(candidate, ["groundingMetadata"])
          finish_reason = get_in(candidate, ["finishReason"])

          if text != "" do
            # Build OpenAI-compatible streaming chunk with grounding metadata
            choice = %{
              index: 0,
              delta: %{
                content: text
              },
              finish_reason: if(finish_reason, do: String.downcase(finish_reason), else: nil)
            }

            # Add grounding metadata to choice if present
            choice =
              if grounding_metadata do
                Map.put(choice, :grounding_metadata, grounding_metadata)
              else
                choice
              end

            openai_chunk = %{
              id: "gemini-stream-#{System.system_time(:millisecond)}",
              object: "chat.completion.chunk",
              created: System.system_time(:second),
              model: "gemini-2.0-flash",
              choices: [choice]
            }

            {:ok, "data: #{Jason.encode!(openai_chunk)}\n\n"}
          else
            :skip
          end

        {:error, err} ->
          Logger.warning("Failed to decode Gemini chunk: #{inspect(err)}")
          :skip
      end
    end
  end

  defp stream_response(conn, id) do
    stream_response(conn, id, "", false)
  end

  defp stream_response(conn, id, error_body, is_error) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} when code >= 200 and code < 300 ->
        # Continue streaming
        stream_response(conn, id, error_body, false)

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        # Error status - will collect error body in chunks
        Logger.error("AI API returned error status: #{code}")
        stream_response(conn, id, error_body, true)

      %HTTPoison.AsyncHeaders{id: ^id} ->
        # Headers received, continue
        stream_response(conn, id, error_body, is_error)

      %HTTPoison.AsyncChunk{id: ^id, chunk: data} ->
        if is_error do
          # Accumulate error response body for logging
          stream_response(conn, id, error_body <> data, true)
        else
          # Forward the chunk normally
          case chunk(conn, data) do
            {:ok, conn} ->
              stream_response(conn, id, error_body, false)

            {:error, _reason} ->
              # Client disconnected
              :ok
          end
        end

      %HTTPoison.AsyncEnd{id: ^id} ->
        if is_error do
          # Log the complete error response
          Logger.error("AI API error response: #{error_body}")

          chunk(
            conn,
            "data: #{Jason.encode!(%{error: %{message: "AI API error"}})}\n\n"
          )

          chunk(conn, "data: [DONE]\n\n")
        end

        # Stream ended
        :ok

      %HTTPoison.Error{id: ^id, reason: reason} ->
        Logger.error("Stream error: #{inspect(reason)}")

        chunk(
          conn,
          "data: #{Jason.encode!(%{error: %{message: "Stream error", reason: inspect(reason)}})}\n\n"
        )

        chunk(conn, "data: [DONE]\n\n")
    after
      60_000 ->
        # Timeout after 60 seconds
        Logger.error("Stream timeout")
        chunk(conn, "data: #{Jason.encode!(%{error: %{message: "Stream timeout"}})}\n\n")
        chunk(conn, "data: [DONE]\n\n")
    end
  end

  defp get_client_ip(conn) do
    # Check for forwarded IP (if behind a proxy/load balancer)
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _others] ->
        # Take the first IP in the chain
        ip
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        # Fall back to remote_ip
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end

  # Check if messages contain image content (for vision model routing)
  defp has_image_content?(%{"messages" => messages}) when is_list(messages) do
    Enum.any?(messages, fn
      %{"content" => content} when is_list(content) ->
        Enum.any?(content, fn
          %{"type" => "image_url"} -> true
          _ -> false
        end)

      _ ->
        false
    end)
  end

  defp has_image_content?(_), do: false

  # Sanitize AI response to only include what clients need
  # Removes model names, usage stats, and provider-specific metadata
  defp sanitize_ai_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"choices" => choices} = response} ->
        # Only return essential fields
        sanitized_choices =
          Enum.map(choices, fn choice ->
            %{
              "index" => choice["index"],
              "message" => %{
                "role" => get_in(choice, ["message", "role"]),
                "content" => get_in(choice, ["message", "content"])
              },
              "finish_reason" => choice["finish_reason"]
            }
          end)

        %{
          "id" => response["id"],
          "object" => response["object"],
          "choices" => sanitized_choices
        }

      {:ok, %{"error" => _} = error_response} ->
        # Pass through error responses as-is
        error_response

      {:error, _} ->
        # If we can't parse, return a generic error
        %{"error" => %{"message" => "Invalid response from AI API"}}
    end
  end
end
