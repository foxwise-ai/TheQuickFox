defmodule TqfApi.Usage.Query do
  use Ecto.Schema
  import Ecto.Changeset

  schema "queries" do
    field(:mode, :string)
    field(:app_name, :string)
    field(:app_bundle_id, :string)
    field(:window_title, :string)
    field(:url, :string)
    field(:metadata, :map)

    belongs_to(:user, TqfApi.Accounts.User)
    belongs_to(:device, TqfApi.Accounts.Device)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(query, attrs) do
    query
    |> cast(attrs, [:mode, :user_id, :device_id, :app_name, :app_bundle_id, :window_title, :url, :metadata])
    |> validate_required([:mode, :user_id, :device_id])
    |> validate_inclusion(:mode, ["respond", "compose", "ask", "code"])
    |> truncate_field(:app_name, 255)
    |> truncate_field(:app_bundle_id, 255)
    |> truncate_field(:window_title, 500)
    |> truncate_field(:url, 2048)
  end
  
  defp truncate_field(changeset, field, max_length) do
    case get_change(changeset, field) do
      nil -> changeset
      value when is_binary(value) ->
        if String.length(value) > max_length do
          put_change(changeset, field, String.slice(value, 0, max_length))
        else
          changeset
        end
      _ -> changeset
    end
  end
end
