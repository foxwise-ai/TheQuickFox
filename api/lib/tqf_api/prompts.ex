defmodule TqfApi.Prompts do
  @moduledoc """
  Context for prompt building and management.
  """

  alias TqfApi.Prompts.PromptBuilder

  @doc """
  Build prompts for the given mode and context.

  Returns `{system_prompt, user_prompt}` tuple.

  ## Parameters
  - mode: :compose | :ask | :code (or string equivalents)
  - user_draft: The user's terse input/query
  - app_info: Map with bundle_id, app_name, window_title
  - context_text: OCR/accessibility extracted text
  - opts: Optional keyword list with :tone (:friendly | :flirty | :formal)
  """
  def build_prompt(mode, user_draft, app_info, context_text, opts \\ []) do
    mode = normalize_mode(mode)
    tone = normalize_tone(opts[:tone])

    PromptBuilder.build(mode, user_draft, app_info, context_text, tone)
  end

  @doc """
  Build OpenAI-compatible messages array from prompts.
  """
  def build_messages(mode, user_draft, app_info, context_text, opts \\ []) do
    {system_prompt, user_prompt} = build_prompt(mode, user_draft, app_info, context_text, opts)

    [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => user_prompt}
    ]
  end

  @doc """
  Build OpenAI-compatible messages with image support.
  """
  def build_messages_with_image(mode, user_draft, app_info, context_text, image_base64, opts \\ []) do
    {system_prompt, user_prompt} = build_prompt(mode, user_draft, app_info, context_text, opts)

    user_content = [
      %{"type" => "text", "text" => user_prompt},
      %{
        "type" => "image_url",
        "image_url" => %{"url" => "data:image/png;base64,#{image_base64}"}
      }
    ]

    [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => user_content}
    ]
  end

  # Normalize mode from string or atom
  defp normalize_mode("compose"), do: :compose
  defp normalize_mode("ask"), do: :ask
  defp normalize_mode("code"), do: :code
  defp normalize_mode(:compose), do: :compose
  defp normalize_mode(:ask), do: :ask
  defp normalize_mode(:code), do: :code
  defp normalize_mode(_), do: :compose

  # Normalize tone from string or atom
  defp normalize_tone("friendly"), do: :friendly
  defp normalize_tone("flirty"), do: :flirty
  defp normalize_tone("formal"), do: :formal
  defp normalize_tone(:friendly), do: :friendly
  defp normalize_tone(:flirty), do: :flirty
  defp normalize_tone(:formal), do: :formal
  defp normalize_tone(nil), do: :friendly
  defp normalize_tone(_), do: :friendly
end
