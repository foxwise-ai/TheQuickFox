//
//  PromptBuilder.swift
//  TheQuickFox
//
//  Constructs structured prompts for ChatGPT based on app context, OCR results,
//  and user input. Maps application categories to appropriate tone settings and
//  handles intelligent context truncation.
//
//  Created for Task 6.
//

import Foundation
import TheQuickFoxCore

// MARK: - Types

/// Mode of operation for the HUD
public enum HUDMode: String, CaseIterable {
    case compose
    case ask
    case code
}

/// Tone options for generated responses
public enum ResponseTone: String, CaseIterable {
    case friendly
    case flirty
    case formal

    var description: String {
        switch self {
        case .friendly:
            return "warm and friendly"
        case .flirty:
            return "playful and flirty. be edgy. if 10/10 is the limit, go 11/10..but keep it tight..reduce use of emojis"
        case .formal:
            return "formal and respectful"
        }
    }
}

/// Application categories for tone mapping
public enum AppCategory: String {
    case email
    case messaging
    case browser
    case socialMedia
    case productivity
    case code
    case unknown

    /// Default tone for this category
    var defaultTone: ResponseTone {
        switch self {
        case .email:
            return .formal
        case .messaging:
            return .friendly
        case .browser:
            return .formal
        case .socialMedia:
            return .friendly
        case .productivity:
            return .formal
        case .code:
            return .formal
        case .unknown:
            return .friendly
        }
    }
}

public struct Result {
    let observations: [[String: Any]]
    let texts: String
    let latencyMs: Double
}

// MARK: - Prompt Builder

public struct PromptBuilder {

    /// Maximum context length in characters (roughly 2k tokens)
    private static let maxContextLength = 8000

    /// Prompt template
    private static let promptTemplate = """
        You're an agent that helps the user write text in an active text box a response to a conversation.

        Below are the details about the active app.

        Please consider application and website/app context when writing to match the original voice of conversation and language. If a person is available in the context, address by name.

        User's desired response (terse and shouldn't be directly used):
        ---
        {draft}
        ---

        Write the response in a professional tone and match voice of the author (responding to conversation).
        Make sure response is complete and do not include variables or placeholders for user to fill in.
        Don't make up information.

        DO NOT precede response with any text.

        Active window: /Applications/Arc.app
        Screenshot: attached
        """

    // MARK: - Helper Functions

    private static func dayOrdinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }

    /// Build a complete prompt for ChatGPT using enhanced context (OCR + Accessibility)
    public static func buildPrompt(
        mode: HUDMode,
        userDraft: String,
        enhancedContext: EnhancedContext,
        tone: ResponseTone? = nil,
        recipientName: String? = nil
    ) -> (system: String, user: String) {

        // Combine OCR and accessibility text for richer context
        let combinedText = buildCombinedContextText(from: enhancedContext)

        return buildPrompt(
            mode: mode,
            userDraft: userDraft,
            appInfo: enhancedContext.appInfo,
            contextText: combinedText,
            tone: tone,
            recipientName: recipientName
        )
    }

    /// Build a complete prompt for ChatGPT (legacy OCR-only version)
    public static func buildPrompt(
        mode: HUDMode,
        userDraft: String,
        appInfo: ActiveWindowInfo,
        ocrText: TextRecognizer.Result,
        tone: ResponseTone? = nil,
        recipientName: String? = nil
    ) -> (system: String, user: String) {

        return buildPrompt(
            mode: mode,
            userDraft: userDraft,
            appInfo: appInfo,
            contextText: ocrText.texts,
            tone: tone,
            recipientName: recipientName
        )
    }

    /// Internal implementation that works with processed context text
    private static func buildPrompt(
        mode: HUDMode,
        userDraft: String,
        appInfo: ActiveWindowInfo,
        contextText: String,
        tone: ResponseTone? = nil,
        recipientName: String? = nil
    ) -> (system: String, user: String) {

        // Log category
        print("bundleID: \(appInfo)")

        // Determine app category and tone
        let category = categorizeApp(bundleID: appInfo.bundleID)
        let selectedTone = tone ?? category.defaultTone

        let now = Date()

        // Custom date formatting for better LLM output
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")

        // Get components
        let calendar = Calendar.current
        let day = calendar.component(.day, from: now)
        let ordinalDay = "\(day)\(dayOrdinalSuffix(for: day))"

        // Format month and year
        dateFormatter.dateFormat = "MMMM"
        let month = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyy"
        let year = dateFormatter.string(from: now)

        // Format time
        dateFormatter.dateFormat = "HH:mm:ss"
        let time = dateFormatter.string(from: now)

        // Format timezone
        dateFormatter.dateFormat = "zzz"
        let timeZone = dateFormatter.string(from: now)

        // Combine all parts
        let formattedDateTime = "\(month) \(ordinalDay), \(year) at \(time) \(timeZone)"

        // Log category
        print("Category: \(category)")

        switch mode {
        case .ask:
            let systemPrompt = """
                You are a skilled assistant with expertise in analyzing app screens from OCR data. The user provides the OCR output of an app screen and asks a question about it. This question may be about web pages, shopping products, UI elements, design feedback, app content, or even visible code or options.

                Your task:
                Analyze the OCR data and answer the user's question as accurately as possible. Use web search if necessary.

                Instructions:
                Infer layout and context if possible based on positioning.
                Be extremely concise, relevant, and accurate. Sacrifice grammar for the sake of concision.
                """

            let userPrompt = """
                App bundleID: \(appInfo.bundleID ?? "unknown")
                App name: \(appInfo.appName ?? "unknown")
                Active window: \(appInfo.windowTitle ?? "unknown")
                Date and time: \(formattedDateTime)
                Context Data:
                \(contextText)

                Question:
                \(userDraft)
                """

            return (system: systemPrompt, user: userPrompt)

        case .compose:
            // use different prompt based on category
            switch category {
            case .code:
                let systemPrompt = """
                    Assist the user to write code to solve queries. Consider the tool at hand. If it's command line, write commands that work well when typed character-by-character. If it's a code editor, write the code to be executed.

                    For command line/terminal:
                    - AVOID heredocs (<<EOF), here-strings, or multi-line shell constructs
                    - AVOID complex pipes or command substitutions that break when typed slowly
                    - PREFER simple commands with output redirection (>, >>)
                    - PREFER multiple echo statements instead of heredocs for multi-line files
                    - PREFER commands that work reliably when each character is typed individually

                    DO NOT include any explanation as this will be used directly in the editor, terminal or command line.
                    """

                let userPrompt = """
                    App bundleID: \(appInfo.bundleID ?? "unknown")
                    App name: \(appInfo.appName ?? "unknown")
                    Active window: \(appInfo.windowTitle ?? "unknown")
                    Context: \(contextText)
                    Date and time: \(formattedDateTime)

                    Assist the user to write code to solve this query:
                    ---
                    \(userDraft)
                    ---
                    """

                return (system: systemPrompt, user: userPrompt)

            default:
                let systemPrompt = """
                    You are an assistant that helps the user draft context-aware replies in an active text box based on the current app and window context.

                    Guidelines:
                    - Use a \(selectedTone.description) tone.
                    - Always match the voice and style of the existing conversation if available.
                    - If a person's name appears, address them by name. Otherwise, remain general.
                    - Do not precede the output with any explanation or notes.
                    - Only write the message content itself.
                    - If the user provides a terse or partial input (e.g., "fixed"), interpret it as intent and expand it into a full response.
                    - Do not invent names, details, or assumptions not found in the visible context.
                    - Do not insert any variables or placeholders like [Your Name], [Company], or similar unless those values appear explicitly in the visible context or the user's provided input.
                    """

                let userPrompt = """
                    App bundleID: \(appInfo.bundleID ?? "unknown")
                    App name: \(appInfo.appName ?? "unknown")
                    Active window: \(appInfo.windowTitle ?? "unknown")

                    Context (visible text):
                    \(contextText)
                    Date and time: \(formattedDateTime)

                    Your task is to rewrite the user input into a polished and appropriate message based on all the context above.

                    User's input (intent to expand):
                    \(userDraft)
                    """

                return (system: systemPrompt, user: userPrompt)
            }

        case .code:
            let systemPrompt = """
                Assist the user to write code to solve queries. Consider the tool at hand. If it's command line, write commands that work well when typed character-by-character. If it's a code editor, write the code to be executed.

                For command line/terminal:
                - AVOID heredocs (<<EOF), here-strings, or multi-line shell constructs
                - AVOID complex pipes or command substitutions that break when typed slowly
                - PREFER simple commands with output redirection (>, >>)
                - PREFER multiple echo statements instead of heredocs for multi-line files
                - PREFER commands that work reliably when each character is typed individually

                DO NOT include any explanation as this will be used directly in the editor, terminal or command line.
                """

            let userPrompt = """
                App bundleID: \(appInfo.bundleID ?? "unknown")
                App name: \(appInfo.appName ?? "unknown")
                Active window: \(appInfo.windowTitle ?? "unknown")
                Context: \(contextText)
                Date and time: \(formattedDateTime)

                Assist the user to write code to solve this query:
                ---
                \(userDraft)
                ---
                """

            return (system: systemPrompt, user: userPrompt)
        }
    }

    /// Parse tone override from user input (e.g., "/friendly hello there")
    public static func parseToneOverride(from input: String) -> (
        tone: ResponseTone?, cleanedInput: String
    ) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("/") else {
            return (nil, input)
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard let command = parts.first else {
            return (nil, input)
        }

        let toneString = String(command.dropFirst())  // Remove "/"
        let tone = ResponseTone.allCases.first { $0.rawValue == toneString.lowercased() }

        if let tone = tone {
            let cleanedInput = parts.count > 1 ? String(parts[1]) : ""
            return (tone, cleanedInput)
        }

        return (nil, input)
    }

    /// Categorize app based on bundle ID
    private static func categorizeApp(bundleID: String?) -> AppCategory {
        guard let bundleID = bundleID?.lowercased() else {
            return .unknown
        }

        switch bundleID {
        case let id where id.contains("mail"):
            return .email
        case "com.apple.messages", "com.facebook.archon", "com.tinyspeck.slackmacgap":
            return .messaging
        case let id
        where id.contains("whatsapp") || id.contains("telegram") || id.contains("discord"):
            return .messaging
        case let id
        where id.contains("safari") || id.contains("chrome") || id.contains("firefox")
            || id.contains("arc"):
            return .browser
        case let id
        where id.contains("twitter") || id.contains("facebook") || id.contains("instagram"):
            return .socialMedia
        case let id
        where id.contains("notion") || id.contains("obsidian") || id.contains("todoist"):
            return .productivity
        case let id
        where id.contains("iterm") || id.contains("terminal"):
            return .code
        default:
            return .unknown
        }
    }

    /// Prepare context from OCR text with intelligent truncation
    private static func prepareContext(ocrText: [String]) -> String {
        let joined = ocrText.joined(separator: "\n")

        if joined.count <= maxContextLength {
            return joined
        }

        // Truncate intelligently - keep beginning and end
        let halfLength = maxContextLength / 2 - 50  // Leave room for ellipsis
        let beginning = String(joined.prefix(halfLength))
        let ending = String(joined.suffix(halfLength))

        return "\(beginning)\n\n[... context truncated ...]\n\n\(ending)"
    }

    /// Estimate token count (rough approximation)
    public static func estimateTokenCount(for text: String) -> Int {
        // Rough estimate: 1 token ≈ 4 characters
        return text.count / 4
    }

    /// Combines OCR, accessibility, and scroll capture data into enriched context text
    private static func buildCombinedContextText(from context: EnhancedContext) -> String {
        var sections: [String] = []

        // Log component sizes for debugging
        let ocrSize = context.ocrData.extractedText.count
        let scrollSize = context.scrollCaptureData?.combinedText.count ?? 0
        let accessibilityTextsSize = context.accessibilityData.extractedTexts.map { $0.text.count }.reduce(0, +)

        LoggingManager.shared.info(.prompt, "📊 PROMPT COMPONENTS:")
        LoggingManager.shared.info(.prompt, "  • OCR text: \(ocrSize) chars (~\(ocrSize/4) tokens)")
        LoggingManager.shared.info(.prompt, "  • Scroll capture: \(scrollSize) chars (~\(scrollSize/4) tokens)")
        LoggingManager.shared.info(.prompt, "  • Accessibility texts: \(accessibilityTextsSize) chars (~\(accessibilityTextsSize/4) tokens)")

        // Prioritize scroll capture text if available and substantially longer
        if let scrollData = context.scrollCaptureData,
            scrollData.combinedText.count > Int(Double(context.ocrData.extractedText.count) * 1.5)
        {
            LoggingManager.shared.info(.prompt, "  • Using scroll capture (larger than OCR)")
            sections.append(
                """
                === EXTENDED CONTENT (AUTO-SCROLL) ===
                \(scrollData.combinedText)
                """)

            sections.append(
                """
                === SCROLL CAPTURE INFO ===
                Frames captured: \(scrollData.frameCount)
                Total characters: \(scrollData.totalCharacters)
                Capture time: \(scrollData.captureLatencyMs.rounded())ms
                """)
        } else {
            // Fall back to OCR text (visible content)
            if !context.ocrData.extractedText.isEmpty {
                LoggingManager.shared.info(.prompt, "  • Using OCR text (primary content)")
                sections.append(
                    """
                    \(context.ocrData)
                    """)
            }
        }

        // Add accessibility text elements (including off-screen content)
        let accessibilityTexts = context.accessibilityData.extractedTexts
        if !accessibilityTexts.isEmpty {
            let visibleTexts = accessibilityTexts.filter { $0.isVisible }
            let hiddenTexts = accessibilityTexts.filter { !$0.isVisible }

            if !visibleTexts.isEmpty {
                let visibleContent = visibleTexts.map { "[\($0.role)] \($0.text)" }.joined(
                    separator: "\n")
                sections.append(
                    """
                    === VISIBLE UI ELEMENTS ===
                    \(visibleContent)
                    """)
            }

            if !hiddenTexts.isEmpty {
                let hiddenContent = hiddenTexts.map { "[\($0.role)] \($0.text)" }.joined(
                    separator: "\n")
                sections.append(
                    """
                    === OFF-SCREEN CONTENT ===
                    \(hiddenContent)
                    """)
            }
        }

        // Add UI structure information
        if let roleTree = context.accessibilityData.roleTree {
            let structure = formatRoleTree(roleTree, depth: 0, maxDepth: 2)
            sections.append(
                """
                === UI STRUCTURE ===
                \(structure)
                """)
        }

        // Add performance info for debugging
        if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
            sections.append(
                """
                === CAPTURE INFO ===
                OCR latency: \(context.ocrData.latencyMs.rounded())ms
                Accessibility latency: \(context.accessibilityData.latencyMs.rounded())ms
                Total elements: OCR=\(context.ocrData.observations.count), AX=\(context.accessibilityData.extractedTexts.count)
                """)
        }

        let finalContext = sections.joined(separator: "\n\n")

        // Log final context size
        LoggingManager.shared.info(.prompt, "  • Final context: \(finalContext.count) chars (~\(finalContext.count/4) tokens)")

        // Warn if context is very large
        if finalContext.count > 100_000 {
            LoggingManager.shared.error(.prompt, "⚠️ LARGE CONTEXT: \(finalContext.count) chars - may exceed token limits")

            // Log context breakdown for debugging massive contexts
            if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
                LoggingManager.shared.debug(.prompt, "Context preview (first 500 chars): \(String(finalContext.prefix(500)))...")
            }
        }

        return finalContext
    }

    /// Format accessibility role tree for context
    private static func formatRoleTree(_ node: AXRoleNode, depth: Int, maxDepth: Int) -> String {
        guard depth <= maxDepth else { return "" }

        let indent = String(repeating: "  ", count: depth)
        var result = "\(indent)- \(node.role)"

        if !node.subroles.isEmpty && depth < maxDepth {
            for subrole in node.subroles.prefix(5) {  // Limit to avoid token overflow
                result += "\n" + formatRoleTree(subrole, depth: depth + 1, maxDepth: maxDepth)
            }
            if node.subroles.count > 5 {
                result += "\n\(indent)  ... (\(node.subroles.count - 5) more)"
            }
        }

        return result
    }
}
