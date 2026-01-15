defmodule TqfApi.UsageFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TqfApi.Usage` context.
  """

  @doc """
  Generate a query.
  """
  def query_fixture(attrs \\ %{}) do
    {:ok, query} =
      attrs
      |> Enum.into(%{
        mode: "some mode"
      })
      |> TqfApi.Usage.create_query()

    query
  end
end
