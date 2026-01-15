defmodule TqfApiWeb.Api.ReleasesController do
  use TqfApiWeb, :controller
  alias TqfApi.Releases

  @doc """
  Create a new release record.
  Internal endpoint for CI/CD workflows.
  """
  def create(conn, params) do
    case Releases.create_app_version(params) do
      {:ok, version} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          version: %{
            id: version.id,
            version: version.version,
            channel: version.channel,
            download_url: version.download_url,
            published_at: version.published_at
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          errors: format_errors(changeset)
        })
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end