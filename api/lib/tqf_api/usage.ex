defmodule TqfApi.Usage do
  @moduledoc """
  The Usage context.
  """

  import Ecto.Query, warn: false
  alias TqfApi.Repo

  alias TqfApi.Usage.Query

  @doc """
  Returns the list of queries.

  ## Examples

      iex> list_queries()
      [%Query{}, ...]

  """
  def list_queries do
    Repo.all(Query)
  end

  @doc """
  Gets a single query.

  Raises `Ecto.NoResultsError` if the Query does not exist.

  ## Examples

      iex> get_query!(123)
      %Query{}

      iex> get_query!(456)
      ** (Ecto.NoResultsError)

  """
  def get_query!(id), do: Repo.get!(Query, id)

  @doc """
  Creates a query.

  ## Examples

      iex> create_query(%{field: value})
      {:ok, %Query{}}

      iex> create_query(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_query(attrs) do
    %Query{}
    |> Query.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a query.

  ## Examples

      iex> update_query(query, %{field: new_value})
      {:ok, %Query{}}

      iex> update_query(query, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_query(%Query{} = query, attrs) do
    query
    |> Query.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a query.

  ## Examples

      iex> delete_query(query)
      {:ok, %Query{}}

      iex> delete_query(query)
      {:error, %Ecto.Changeset{}}

  """
  def delete_query(%Query{} = query) do
    Repo.delete(query)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking query changes.

  ## Examples

      iex> change_query(query)
      %Ecto.Changeset{data: %Query{}}

  """
  def change_query(%Query{} = query, attrs \\ %{}) do
    Query.changeset(query, attrs)
  end

  @doc """
  Counts queries for a user today.

  ## Examples

      iex> count_queries_today(123)
      5

  """
  def count_queries_today(user_id) do
    today = Date.utc_today()
    beginning_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")

    Query
    |> where([q], q.user_id == ^user_id)
    |> where([q], q.inserted_at >= ^beginning_of_day)
    |> Repo.aggregate(:count, :id)
  end
end
