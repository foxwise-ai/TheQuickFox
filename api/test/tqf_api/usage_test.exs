defmodule TqfApi.UsageTest do
  use TqfApi.DataCase

  alias TqfApi.Usage

  describe "queries" do
    alias TqfApi.Usage.Query

    import TqfApi.UsageFixtures

    @invalid_attrs %{mode: nil}

    test "list_queries/0 returns all queries" do
      query = query_fixture()
      assert Usage.list_queries() == [query]
    end

    test "get_query!/1 returns the query with given id" do
      query = query_fixture()
      assert Usage.get_query!(query.id) == query
    end

    test "create_query/1 with valid data creates a query" do
      valid_attrs = %{mode: "some mode"}

      assert {:ok, %Query{} = query} = Usage.create_query(valid_attrs)
      assert query.mode == "some mode"
    end

    test "create_query/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Usage.create_query(@invalid_attrs)
    end

    test "update_query/2 with valid data updates the query" do
      query = query_fixture()
      update_attrs = %{mode: "some updated mode"}

      assert {:ok, %Query{} = query} = Usage.update_query(query, update_attrs)
      assert query.mode == "some updated mode"
    end

    test "update_query/2 with invalid data returns error changeset" do
      query = query_fixture()
      assert {:error, %Ecto.Changeset{}} = Usage.update_query(query, @invalid_attrs)
      assert query == Usage.get_query!(query.id)
    end

    test "delete_query/1 deletes the query" do
      query = query_fixture()
      assert {:ok, %Query{}} = Usage.delete_query(query)
      assert_raise Ecto.NoResultsError, fn -> Usage.get_query!(query.id) end
    end

    test "change_query/1 returns a query changeset" do
      query = query_fixture()
      assert %Ecto.Changeset{} = Usage.change_query(query)
    end
  end
end
