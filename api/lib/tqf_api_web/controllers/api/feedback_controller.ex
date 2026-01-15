defmodule TqfApiWeb.Api.FeedbackController do
  use TqfApiWeb, :controller

  alias TqfApi.Feedback
  alias TqfApi.Feedback.FeedbackEntry

  @max_upload_size 10_485_760  # 10MB
  @allowed_content_types ["application/zip", "application/x-zip", "application/x-zip-compressed"]

  def create(conn, %{"message" => message} = params) do
    user = conn.assigns.current_device.user
    
    require Logger
    Logger.debug("Creating feedback for user #{user.id}")

    # Create feedback record
    with {:ok, feedback} <- create_feedback(user, message, params) do
      # Handle log file upload if present
      case Map.get(params, "logs") do
        %Plug.Upload{} = upload ->
          process_log_upload(feedback, upload)
        _ ->
          :ok
      end

      json(conn, %{
        success: true,
        feedback_id: feedback.id,
        message: "Feedback submitted successfully"
      })
    else
      {:error, changeset} ->
        Logger.error("Feedback creation failed: #{inspect(changeset.errors)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          errors: format_changeset_errors(changeset),
          error: "Validation failed"
        })
    end
  end

  def upload_logs(conn, %{"feedback_id" => feedback_id, "logs" => %Plug.Upload{} = upload}) do
    user = conn.assigns.current_device.user

    # Verify feedback belongs to user
    with {:ok, feedback} <- get_user_feedback(user, feedback_id),
         :ok <- validate_upload(upload),
         {:ok, _} <- process_log_upload(feedback, upload) do
      json(conn, %{
        success: true,
        message: "Logs uploaded successfully"
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Feedback not found"})
      
      {:error, :invalid_file} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid file type or size"})
      
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: "Upload failed", details: reason})
    end
  end

  # Private functions

  defp create_feedback(user, message, params) do
    metadata = %{
      device_id: params["device_id"],
      app_version: params["app_version"],
      os_version: params["os_version"],
      timestamp: params["timestamp"],
      category: params["category"] || "general"
    }

    Feedback.create_feedback(%{
      user_id: user.id,
      message: message,
      metadata: metadata,
      status: "pending"
    })
  end

  defp get_user_feedback(user, feedback_id) do
    case Feedback.get_feedback_by_id_and_user(feedback_id, user.id) do
      nil -> {:error, :not_found}
      feedback -> {:ok, feedback}
    end
  end

  defp validate_upload(%Plug.Upload{} = upload) do
    # Get file size from the actual file
    file_size = case File.stat(upload.path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
    
    cond do
      file_size > @max_upload_size ->
        {:error, :invalid_file}
      
      file_size == 0 ->
        {:error, :invalid_file}
      
      upload.content_type not in @allowed_content_types ->
        {:error, :invalid_file}
      
      true ->
        :ok
    end
  end

  defp process_log_upload(feedback, %Plug.Upload{} = upload) do
    # Generate unique filename
    extension = Path.extname(upload.filename)
    filename = "#{feedback.id}-#{:os.system_time(:millisecond)}#{extension}"
    
    # Get file size
    file_size = case File.stat(upload.path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
    
    # Store in S3 or local storage
    case store_log_file(filename, upload.path) do
      {:ok, url} ->
        # Create log record
        {:ok, _log} = Feedback.create_feedback_log(feedback.id, %{
          filename: upload.filename,
          size: file_size,
          content_type: upload.content_type,
          storage_path: url
        })
        
        # Update feedback with log URL
        Feedback.update_feedback(feedback, %{
          log_url: url,
          has_logs: true
        })
      
      {:error, _reason} = error ->
        error
    end
  end

  defp store_log_file(filename, source_path) do
    # For now, store locally - in production, use S3
    storage_dir = Application.get_env(:tqf_api, :feedback_storage_path) || "/tmp/tqf-feedback"
    File.mkdir_p!(storage_dir)
    
    dest_path = Path.join(storage_dir, filename)
    
    case File.copy(source_path, dest_path) do
      {:ok, _} -> 
        {:ok, "/storage/feedback/#{filename}"}
      {:error, reason} -> 
        {:error, reason}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end