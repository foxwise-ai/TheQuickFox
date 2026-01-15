defmodule TqfApiWeb.Api.DownloadController do
  use TqfApiWeb, :controller

  @doc """
  Serves release files for Sparkle updates.
  In development: serves from local directory
  In production: redirects to CDN
  """
  def release(conn, %{"filename" => filename}) do
    # Only allow .zip files for security
    unless String.ends_with?(filename, ".zip") do
      conn
      |> put_status(403)
      |> json(%{error: "Invalid file type"})
    else
      case Application.get_env(:tqf_api, :environment) do
        :prod ->
          # In production, redirect to CDN
          cdn_url = get_cdn_url(filename)
          
          conn
          |> put_status(302)
          |> put_resp_header("location", cdn_url)
          |> put_resp_header("cache-control", "public, max-age=3600")
          |> text("")
          
        _ ->
          # In development, serve from local directory
          file_path = Path.join([System.user_home!(), "Downloads", "test-releases", filename])
          
          if File.exists?(file_path) do
            conn
            |> put_resp_header("content-type", "application/zip")
            |> send_file(200, file_path)
          else
            conn
            |> put_status(404)
            |> json(%{error: "File not found"})
          end
      end
    end
  end
  
  defp get_cdn_url(filename) do
    cdn_base = Application.get_env(:tqf_api, :cdn_base_url)
    "#{cdn_base}/releases/#{filename}"
  end
end