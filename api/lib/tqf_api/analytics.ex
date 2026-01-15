defmodule TqfApi.Analytics do
  @moduledoc """
  The Analytics context for aggregating usage metrics and statistics.
  """

  import Ecto.Query, warn: false
  alias TqfApi.Repo
  alias TqfApi.Usage.Query

  @doc """
  Get comprehensive analytics metrics for a user within a time range.

  ## Parameters
    - user_id: The user's ID
    - time_range: "7d", "30d", or "all"

  ## Returns
    A map containing:
    - total_queries: Total query count
    - queries_by_mode: Map of mode to count
    - top_apps: List of most used apps with counts
    - current_streak: Days in a row with at least one query
    - longest_streak: Best streak ever
    - time_saved_minutes: Estimated time saved (5 min per query)
    - queries_by_hour: Distribution of queries by hour of day
    - daily_usage: Daily query counts for trends
    - time_range: The time range used
  """
  def get_metrics(user_id, time_range \\ "30d") do
    since = parse_time_range(time_range)

    %{
      total_queries: total_queries(user_id, since),
      queries_by_mode: queries_by_mode(user_id, since),
      top_apps: top_apps(user_id, 5, since),
      current_streak: calculate_streak(user_id),
      longest_streak: calculate_longest_streak(user_id),
      time_saved_minutes: calculate_time_saved(user_id, since),
      queries_by_hour: queries_by_hour(user_id, since),
      daily_usage: daily_usage(user_id, since),
      time_range: time_range
    }
  end

  @doc """
  Parse time range string into DateTime.
  """
  defp parse_time_range("7d") do
    DateTime.utc_now() |> DateTime.add(-7, :day)
  end

  defp parse_time_range("30d") do
    DateTime.utc_now() |> DateTime.add(-30, :day)
  end

  defp parse_time_range("all") do
    ~U[2000-01-01 00:00:00Z]
  end

  defp parse_time_range(_), do: parse_time_range("30d")

  @doc """
  Count total queries for a user within time range.
  """
  def total_queries(user_id, since) do
    Query
    |> where([q], q.user_id == ^user_id)
    |> where([q], q.inserted_at >= ^since)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Get query counts broken down by mode.

  Returns a map like: %{"compose" => 45, "code" => 23, "ask" => 12}
  """
  def queries_by_mode(user_id, since) do
    Query
    |> where([q], q.user_id == ^user_id)
    |> where([q], q.inserted_at >= ^since)
    |> group_by([q], q.mode)
    |> select([q], {q.mode, count(q.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Get top N most used apps with their query counts.

  Returns list like: [%{app_name: "Slack", app_bundle_id: "com.tinyspeck.slackmacgap", count: 15}, ...]
  """
  def top_apps(user_id, limit \\ 5, since) do
    Query
    |> where([q], q.user_id == ^user_id)
    |> where([q], q.inserted_at >= ^since)
    |> where([q], not is_nil(q.app_name))
    |> group_by([q], [q.app_name, q.app_bundle_id])
    |> select([q], %{
      app_name: q.app_name,
      app_bundle_id: q.app_bundle_id,
      count: count(q.id)
    })
    |> order_by([q], desc: count(q.id))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Calculate current active streak (consecutive days with at least 1 query).

  Returns number of days in a row (including today if used today).
  """
  def calculate_streak(user_id) do
    # Get all unique dates the user has made queries, ordered descending
    query_dates =
      Query
      |> where([q], q.user_id == ^user_id)
      |> select([q], fragment("DATE(?)", q.inserted_at))
      |> distinct(true)
      |> order_by([q], desc: fragment("DATE(?)", q.inserted_at))
      |> Repo.all()

    # fragment("DATE(?)", ...) returns Date structs directly, no parsing needed

    if Enum.empty?(query_dates) do
      0
    else
      calculate_current_streak(query_dates, Date.utc_today())
    end
  end

  defp calculate_current_streak([], _today), do: 0

  defp calculate_current_streak([most_recent_date | rest_dates], today) do
    # Check if the streak is active (used today or yesterday)
    days_since_last = Date.diff(today, most_recent_date)

    if days_since_last > 1 do
      # Streak is broken
      0
    else
      # Count consecutive days backwards
      count_consecutive_days([most_recent_date | rest_dates], 1)
    end
  end

  defp count_consecutive_days([_single], streak), do: streak

  defp count_consecutive_days([date1, date2 | rest], streak) do
    if Date.diff(date1, date2) == 1 do
      # Consecutive day found, continue
      count_consecutive_days([date2 | rest], streak + 1)
    else
      # Gap found, return current streak
      streak
    end
  end

  @doc """
  Calculate the longest streak ever for a user.
  """
  def calculate_longest_streak(user_id) do
    query_dates =
      Query
      |> where([q], q.user_id == ^user_id)
      |> select([q], fragment("DATE(?)", q.inserted_at))
      |> distinct(true)
      |> order_by([q], desc: fragment("DATE(?)", q.inserted_at))
      |> Repo.all()

    # fragment("DATE(?)", ...) returns Date structs directly, no parsing needed

    if Enum.empty?(query_dates) do
      0
    else
      find_longest_streak(query_dates)
    end
  end

  defp find_longest_streak(dates) do
    dates
    |> find_all_streaks(1, 1, [])
    |> Enum.max(fn -> 0 end)
  end

  defp find_all_streaks([_single], current_streak, _max_streak, streaks) do
    [current_streak | streaks]
  end

  defp find_all_streaks([date1, date2 | rest], current_streak, max_streak, streaks) do
    if Date.diff(date1, date2) == 1 do
      # Consecutive, increment current streak
      new_max = max(current_streak + 1, max_streak)
      find_all_streaks([date2 | rest], current_streak + 1, new_max, streaks)
    else
      # Gap found, save current streak and start new one
      find_all_streaks([date2 | rest], 1, max_streak, [current_streak | streaks])
    end
  end

  @doc """
  Calculate estimated time saved based on query count.

  Assumes each query saves approximately 5 minutes of typing/thinking time.
  """
  def calculate_time_saved(user_id, since) do
    query_count = total_queries(user_id, since)
    # 5 minutes per query on average
    query_count * 1
  end

  @doc """
  Get query distribution by hour of day (0-23).

  Returns map like: %{9 => 15, 10 => 23, 14 => 18, ...}
  """
  def queries_by_hour(user_id, since) do
    Query
    |> where([q], q.user_id == ^user_id)
    |> where([q], q.inserted_at >= ^since)
    |> select([q], {fragment("EXTRACT(HOUR FROM ?)", q.inserted_at), count(q.id)})
    |> group_by([q], fragment("EXTRACT(HOUR FROM ?)", q.inserted_at))
    |> Repo.all()
    |> Enum.map(fn {hour, count} ->
      # EXTRACT returns a Decimal, convert to integer
      hour_int = Decimal.to_integer(hour)
      {hour_int, count}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Get daily query counts for trend visualization.

  Returns list like: [%{date: "2024-01-15", count: 12}, ...]
  """
  def daily_usage(user_id, since) do
    Query
    |> where([q], q.user_id == ^user_id)
    |> where([q], q.inserted_at >= ^since)
    |> select([q], {fragment("DATE(?)", q.inserted_at), count(q.id)})
    |> group_by([q], fragment("DATE(?)", q.inserted_at))
    |> order_by([q], asc: fragment("DATE(?)", q.inserted_at))
    |> Repo.all()
    |> Enum.map(fn {date, count} ->
      # date is already a Date struct, just convert to ISO8601 string
      %{date: Date.to_iso8601(date), count: count}
    end)
  end
end
