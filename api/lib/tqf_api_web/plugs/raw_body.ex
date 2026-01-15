defmodule TqfApiWeb.Plugs.RawBody do
  @moduledoc """
  Captures raw body for Stripe webhook signature verification
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.assign(conn, :raw_body, body)
  end
end
