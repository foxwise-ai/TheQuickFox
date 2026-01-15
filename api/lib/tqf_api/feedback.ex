defmodule TqfApi.Feedback do
  @moduledoc """
  Context module for user feedback and log management
  """

  import Ecto.Query, warn: false
  alias TqfApi.Repo
  alias TqfApi.Feedback.FeedbackEntry
  alias TqfApi.Feedback.FeedbackLog

  @doc """
  Creates a new feedback entry
  """
  def create_feedback(attrs \\ %{}) do
    %FeedbackEntry{}
    |> FeedbackEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a feedback entry by ID
  """
  def get_feedback_by_id(id) do
    Repo.get(FeedbackEntry, id)
  end

  @doc """
  Gets a feedback entry by ID and user ID
  """
  def get_feedback_by_id_and_user(id, user_id) do
    Repo.get_by(FeedbackEntry, id: id, user_id: user_id)
  end

  @doc """
  Updates a feedback entry
  """
  def update_feedback(%FeedbackEntry{} = feedback, attrs) do
    feedback
    |> FeedbackEntry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists feedback entries with pagination
  """
  def list_feedback(params \\ %{}) do
    query = from f in FeedbackEntry,
      order_by: [desc: f.inserted_at]

    query = if status = params[:status] do
      where(query, [f], f.status == ^status)
    else
      query
    end

    query = if user_id = params[:user_id] do
      where(query, [f], f.user_id == ^user_id)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Creates a log entry for feedback
  """
  def create_feedback_log(feedback_id, attrs) do
    attrs = Map.put(attrs, :feedback_id, feedback_id)
    
    %FeedbackLog{}
    |> FeedbackLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets recent feedback statistics
  """
  def get_feedback_stats(days \\ 7) do
    since = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)
    
    query = from f in FeedbackEntry,
      where: f.inserted_at >= ^since,
      select: %{
        total: count(f.id),
        with_logs: count(fragment("CASE WHEN ? = true THEN 1 END", f.has_logs)),
        by_status: fragment("json_object_agg(?, count(*))", f.status)
      }
    
    Repo.one(query)
  end
end