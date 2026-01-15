defmodule TqfApiWeb.CheckoutController do
  use TqfApiWeb, :controller

  def success(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Path.join(:code.priv_dir(:tqf_api), "static/checkout/success.html"))
  end

  def cancel(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Path.join(:code.priv_dir(:tqf_api), "static/checkout/cancel.html"))
  end
end