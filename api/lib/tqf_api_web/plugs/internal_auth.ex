defmodule TqfApiWeb.Plugs.InternalAuth do
  @moduledoc """
  Authentication plug for internal/admin endpoints.
  Validates a bearer token against INTERNAL_API_TOKEN env var.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- valid_token?(token) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
        |> halt()
    end
  end

  defp valid_token?(token) do
    expected_token = System.get_env("INTERNAL_API_TOKEN")
    
    if expected_token && expected_token != "" do
      Plug.Crypto.secure_compare(token, expected_token)
    else
      false
    end
  end
end