defmodule TqfApiWeb.ExtensionController do
  use TqfApiWeb, :controller

  def welcome(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Path.join(:code.priv_dir(:tqf_api), "static/extension/welcome.html"))
  end

  def verified(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Path.join(:code.priv_dir(:tqf_api), "static/extension/verified.html"))
  end
end
