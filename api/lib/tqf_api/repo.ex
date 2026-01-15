defmodule TqfApi.Repo do
  use Ecto.Repo,
    otp_app: :tqf_api,
    adapter: Ecto.Adapters.Postgres
end
