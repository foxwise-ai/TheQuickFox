defmodule TqfApi.Prompts.PromptBuilder do
  @moduledoc """
  Constructs structured prompts for AI based on mode, app context, and user input.
  Ported from Swift PromptBuilder.swift.
  """

  @type mode :: :compose | :ask | :code
  @type tone :: :friendly | :flirty | :formal
  @type app_info :: %{
          optional(:bundle_id) => String.t() | nil,
          optional(:app_name) => String.t() | nil,
          optional(:window_title) => String.t() | nil
        }

  @doc """
  Build a complete prompt for the AI.

  Returns `{system_prompt, user_prompt}` tuple.

  ## Parameters
  - mode: :compose | :ask | :code
  - user_draft: The user's terse input/query
  - app_info: Map with :bundle_id, :app_name, :window_title
  - context_text: OCR/accessibility extracted text
  - tone: :friendly | :flirty | :formal (only used for compose mode)
  """
  @spec build(mode(), String.t(), app_info(), String.t(), tone()) :: {String.t(), String.t()}
  def build(mode, user_draft, app_info, context_text, tone \\ :friendly) do
    datetime = format_datetime()

    bundle_id = app_info[:bundle_id] || app_info["bundle_id"] || "unknown"
    app_name = app_info[:app_name] || app_info["app_name"] || "unknown"
    window_title = app_info[:window_title] || app_info["window_title"] || "unknown"

    case mode do
      :ask ->
        build_ask_prompt(user_draft, bundle_id, app_name, window_title, context_text, datetime)

      :code ->
        build_code_prompt(user_draft, bundle_id, app_name, window_title, context_text, datetime)

      :compose ->
        build_compose_prompt(
          user_draft,
          bundle_id,
          app_name,
          window_title,
          context_text,
          datetime,
          tone
        )
    end
  end

  @doc """
  Get tone description string for prompt injection.
  """
  @spec tone_description(tone()) :: String.t()
  def tone_description(:friendly), do: "warm and friendly"

  def tone_description(:flirty),
    do:
      "playful and flirty. be edgy. if 10/10 is the limit, go 11/10..but keep it tight..reduce use of emojis"

  def tone_description(:formal), do: "formal and respectful"

  # ASK mode - for questions about screen content
  defp build_ask_prompt(user_draft, bundle_id, app_name, window_title, context_text, datetime) do
    system = """
    You are a skilled assistant with expertise in analyzing app screens from OCR data. The user provides the OCR output of an app screen and asks a question about it. This question may be about web pages, shopping products, UI elements, design feedback, app content, or even visible code or options.

    Your task:
    Analyze the OCR data and answer the user's question as accurately as possible. Use web search if necessary.

    OCR Data Format:
    The context includes OCR observations with quad coordinates. Coordinates are normalized (0-1) with origin at top-left: x=0 is left edge, x=1 is right edge, y=0 is top, y=1 is bottom. Use these positions to understand spatial layout (e.g., headers at top, sidebars on left/right, buttons near each other).

    Instructions:
    Infer layout and context based on text positioning.
    Be concise, relevant, and accurate.
    """

    user = """
    App bundleID: #{bundle_id}
    App name: #{app_name}
    Active window: #{window_title}
    Date and time: #{datetime}
    Context Data:
    #{context_text}

    Question:
    #{user_draft}
    """

    {String.trim(system), String.trim(user)}
  end

  # CODE mode - for writing code/commands
  defp build_code_prompt(user_draft, bundle_id, app_name, window_title, context_text, datetime) do
    system = """
    Assist the user to write code to solve queries. Consider the tool at hand. If it's command line, write commands that work well when typed character-by-character. If it's a code editor, write the code to be executed.

    OCR Data Format:
    The context includes OCR observations with quad coordinates. Coordinates are normalized (0-1) with origin at top-left: x=0 is left edge, x=1 is right edge, y=0 is top, y=1 is bottom.

    For command line/terminal:
    - AVOID heredocs (<<EOF), here-strings, or multi-line shell constructs
    - AVOID complex pipes or command substitutions that break when typed slowly
    - PREFER simple commands with output redirection (>, >>)
    - PREFER multiple echo statements instead of heredocs for multi-line files
    - PREFER commands that work reliably when each character is typed individually

    DO NOT include any explanation as this will be used directly in the editor, terminal or command line.
    """

    user = """
    App bundleID: #{bundle_id}
    App name: #{app_name}
    Active window: #{window_title}
    Context: #{context_text}
    Date and time: #{datetime}

    Assist the user to write code to solve this query:
    ---
    #{user_draft}
    ---
    """

    {String.trim(system), String.trim(user)}
  end

  # COMPOSE mode - for writing messages/emails
  defp build_compose_prompt(
         user_draft,
         bundle_id,
         app_name,
         window_title,
         context_text,
         datetime,
         tone
       ) do
    tone_desc = tone_description(tone)

    system = """
    You are an assistant that helps the user draft context-aware replies in an active text box based on the current app and window context.

    OCR Data Format:
    The context includes OCR observations with quad coordinates. Coordinates are normalized (0-1) with origin at top-left: x=0 is left edge, x=1 is right edge, y=0 is top, y=1 is bottom. Use positions to understand layout (headers at top, reply boxes below messages, etc.).

    Guidelines:
    - Use a #{tone_desc} tone.
    - Avoid em-dashes (—) in writing.
    - Always match the voice and style of the existing conversation if available.
    - If a person's name appears, address them by name. Otherwise, remain general.
    - Do not precede the output with any explanation or notes.
    - Only write the message content itself.
    - If the user provides a terse or partial input (e.g., "fixed"), interpret it as intent and expand it into a full response.
    - Do not invent names, details, or assumptions not found in the visible context.
    - Do not insert any variables or placeholders like [Your Name], [Company], or similar unless those values appear explicitly in the visible context or the user's provided input.
    """

    user = """
    App bundleID: #{bundle_id}
    App name: #{app_name}
    Active window: #{window_title}

    Context (visible text):
    #{context_text}
    Date and time: #{datetime}

    Your task is to rewrite the user input into a polished and appropriate message based on all the context above.

    User's input (intent to expand):
    #{user_draft}
    """

    {String.trim(system), String.trim(user)}
  end

  # Format current datetime in a human-friendly way
  defp format_datetime do
    now = DateTime.utc_now()
    day = now.day

    suffix =
      case rem(day, 10) do
        1 when day != 11 -> "st"
        2 when day != 12 -> "nd"
        3 when day != 13 -> "rd"
        _ -> "th"
      end

    month = Calendar.strftime(now, "%B")
    year = now.year
    time = Calendar.strftime(now, "%H:%M:%S")

    "#{month} #{day}#{suffix}, #{year} at #{time} UTC"
  end
end
