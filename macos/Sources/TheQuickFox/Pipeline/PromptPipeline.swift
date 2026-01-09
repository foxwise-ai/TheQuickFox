//
//  PromptPipeline.swift
//  TheQuickFox
//
//  Coordinates the full flow:
//
//   1. Capture screenshot of front-most window
//   2. Build prompt with PromptBuilder
//   3. Stream completion tokens using GeminiStreamClient
//   4. Feed incremental updates back to delegate
//   5. On completion, insert reply via FocusManager
//
//  The pipeline is designed to be UI-agnostic; HUD implements the delegate to
//  receive streaming updates and completion/error notifications.
//

import AppKit
import Foundation
import os

// MARK: – Delegate

public struct GroundingMetadata: Codable {
    public struct GroundingSupport: Codable {
        public struct Segment: Codable {
            public let startIndex: Int
            public let endIndex: Int
            public let text: String
        }
        public let segment: Segment
        public let groundingChunkIndices: [Int]
    }
    public struct GroundingChunk: Codable {
        public struct Web: Codable {
            public let uri: String
            public let title: String?
        }
        public let web: Web?
    }
    public let groundingSupports: [GroundingSupport]?
    public let groundingChunks: [GroundingChunk]?
}

public protocol PromptPipelineDelegate: AnyObject {
    /// Called when streaming delivers a new chunk.
    func pipeline(_ pipeline: PromptPipeline, didReceive token: String)
    /// Called when the pipeline finishes successfully with the full reply.
    func pipeline(_ pipeline: PromptPipeline, didComplete reply: String)
    /// Called when grounding metadata is available (for web search results).
    func pipeline(_ pipeline: PromptPipeline, didReceiveGroundingMetadata metadata: GroundingMetadata)
    /// Called on cancellation or error.
    func pipeline(_ pipeline: PromptPipeline, didFail error: Error)
}

// MARK: – Pipeline Coordinator

public final class PromptPipeline {

    public enum PipelineError: Error, LocalizedError {
        case openAiApiKeyMissing
        case geminiApiKeyMissing
        case anthropicApiKeyMissing
        case cancelled
        case screenshotUnavailable

        public var errorDescription: String? {
            switch self {
            case .openAiApiKeyMissing:
                return "No API key found. Please set OPENAI_API_KEY in your environment variables."
            case .geminiApiKeyMissing:
                return "No API key found. Please set GEMINI_API_KEY in your environment variables."
            case .anthropicApiKeyMissing:
                return
                    "No API key found. Please set ANTHROPIC_API_KEY in your environment variables."
            case .cancelled:
                return "The operation was cancelled."
            case .screenshotUnavailable:
                return "Screenshot capture failed. Screen recording permissions may be required."
            }
        }
    }

    // MARK: State

    private let userDraft: String
    private var cancellationFlag = false
    private weak var delegate: PromptPipelineDelegate?

    private let openAiApiKey: String
    private let geminiApiKey: String
    private let anthropicApiKey: String
    private let cachedScreenshot: WindowScreenshot?
    private let mode: HUDMode
    private let tone: ResponseTone?
    private let autoInsertText: Bool
    private let isDemoMode: Bool

    // MARK: Init

    public init(
        userDraft: String,
        openAiApiKey: String?,
        geminiApiKey: String?,
        anthropicApiKey: String?,
        delegate: PromptPipelineDelegate,
        cachedScreenshot: WindowScreenshot? = nil,
        mode: HUDMode,
        tone: ResponseTone?,
        autoInsertText: Bool = true,
        isDemoMode: Bool = false
    ) throws {
        // API keys are optional since all requests go through proxy
        self.userDraft = userDraft
        self.openAiApiKey = openAiApiKey ?? ""
        self.geminiApiKey = geminiApiKey ?? ""
        self.anthropicApiKey = anthropicApiKey ?? ""
        self.delegate = delegate
        self.cachedScreenshot = cachedScreenshot
        self.mode = mode
        self.tone = tone
        self.autoInsertText = autoInsertText
        self.isDemoMode = isDemoMode
    }

    // MARK: Public control

    public func start() {
        Task.detached { [weak self] in
            await self?._run()
        }
    }

    public func cancel() {
        cancellationFlag = true
    }

    // MARK: Private run loop

    @MainActor
    private func _run() async {

        // Start a logging session for this pipeline execution
        let sessionId = LoggingSystem.shared.startSession(
            trigger: "pipeline_execution",
            metadata: [
                "mode": AnyCodable(mode.rawValue),
                "tone": AnyCodable(tone?.rawValue ?? "none"),
                "query_length": AnyCodable(userDraft.count),
                "demo_mode": AnyCodable(isDemoMode)
            ]
        )

        do {
            // We'll track usage after we have the context information

            let enhancedContext: EnhancedContext
            let shot: WindowScreenshot?

            if isDemoMode {
                // Demo mode: create minimal context with hardcoded OCR data
                LoggingSystem.shared.logInfo(.pipeline, "Running in demo mode with hardcoded OCR data", sessionId: sessionId)

                // Create minimal app info for demo
                let demoAppInfo = ActiveWindowInfo(
                    bundleID: "com.foxwiseai.thequickfox.onboarding",
                    appName: "Support Portal",
                    windowTitle: "Customer Support - Demo",
                    pid: ProcessInfo.processInfo.processIdentifier
                )

                // Create OCR data from demo content
                let ocrText = """
                    Support Portal

                    buzz@killington.com:
                    Cancel my account

                    Reply:
                    Type your reply...
                    """
                let demoOCRData = OCRData(
                    observations: [],
                    extractedText: ocrText,
                    latencyMs: 0
                )

                // Create minimal accessibility data
                let demoAccessibilityData = AccessibilityData(
                    roleTree: nil,
                    extractedTexts: [],
                    uiElements: [],
                    latencyMs: 0,
                    error: "Demo mode - no accessibility data"
                )

                enhancedContext = EnhancedContext(
                    appInfo: demoAppInfo,
                    ocrData: demoOCRData,
                    accessibilityData: demoAccessibilityData,
                    scrollCaptureData: nil,
                    captureLatencyMs: 0
                )

                // In demo mode with a screenshot (e.g., logo page), use it
                if isDemoMode && cachedScreenshot != nil {
                    shot = cachedScreenshot
                } else {
                    shot = nil
                }
            } else {
                // Normal mode: use cached screenshot
                LoggingManager.shared.info(
                    .screenshot, "Checking cached screenshot - available: \(cachedScreenshot != nil)")
                if let screenshot = cachedScreenshot {
                    LoggingManager.shared.info(
                        .screenshot, "Cached screenshot details - app: \(screenshot.activeInfo.appName ?? "nil"), size: \(screenshot.image.size)")
                }

                guard let screenshot = cachedScreenshot else {
                    LoggingManager.shared.error(
                        .screenshot, "No cached screenshot available - likely missing permissions")
                    // Post notification to show onboarding with permissions error
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ShowOnboardingPermissionsError"),
                            object: nil
                        )
                    }
                    throw PipelineError.screenshotUnavailable
                }
                shot = screenshot
                LoggingManager.shared.info(
                    .screenshot, "Using cached screenshot from initial Control+Control trigger")

                // Persist screenshot to a temp file when dev logging is enabled
                if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
                    if let url = try? WindowScreenshotter.saveToTemporary(
                        screenshot, prefix: "PromptPipeline")
                    {
                        LoggingManager.shared.debug(.screenshot, "Screenshot saved to \(url.path)")
                    }
                }

                if cancellationFlag { throw PipelineError.cancelled }

                // 2. Capture enhanced context (OCR + Accessibility + Auto-scroll)
                enhancedContext = try await EnhancedContextProvider.capture(
                    from: screenshot,
                    includeAccessibility: false,
                    maxAccessibilityDepth: 6,
                    // enableScrollCapture: true,
                    scrollConfig: .conservative
                )
            }

            // 3. Parse tone override from user input
            let (toneOverride, cleanedDraft) = PromptBuilder.parseToneOverride(from: userDraft)
            let finalTone = toneOverride ?? self.tone

            // Build context using TOON format for token efficiency (30-80% reduction vs JSON)
            let contextText: String
            do {
                contextText = try enhancedContext.ocrData.toTOON()
                LoggingManager.shared.debug(.prompt, "TOON context size: \(contextText.count) bytes")
            } catch {
                // Fallback to plain text if TOON encoding fails
                LoggingManager.shared.error(.prompt, "TOON encoding failed, using plain text: \(error)")
                contextText = enhancedContext.ocrData.extractedText
            }

            LoggingManager.shared.info(
                .prompt,
                "Sending to API - mode: \(self.mode.rawValue), tone: \(finalTone?.rawValue ?? "default"), context from \(enhancedContext.appInfo.appName ?? "Unknown App")"
            )

            // Track usage with API (blocking to catch quota errors early)
            do {
                // Extract browser URL only for API analytics (not sent to LLM)
                let browserURL = BrowserURLExtractor.extractURL(from: enhancedContext.appInfo)

                let response = try await APIClient.shared.trackUsage(
                    mode: self.mode,
                    appInfo: enhancedContext.appInfo,
                    browserURL: browserURL
                )
                LoggingManager.shared.info(
                    .generic, "Query tracked. Remaining: \(response.data.trial_queries_remaining)")

                // Check if we're running low on queries
                if response.data.trial_queries_remaining <= 2 && response.data.trial_queries_remaining > 0 {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowTrialWarning"),
                        object: nil,
                        userInfo: ["remaining": response.data.trial_queries_remaining]
                    )
                }
            } catch APIError.quotaExceeded {
                LoggingSystem.shared.logWarning(.pipeline, "Trial quota exceeded - stopping pipeline", sessionId: sessionId, metadata: [
                    "trial_queries_remaining": AnyCodable(0)
                ])
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowUpgradePrompt"),
                    object: nil
                )
                self.delegate?.pipeline(self, didFail: APIError.quotaExceeded)
                return  // Stop here - don't make LLM request
            } catch APIError.termsRequired {
                LoggingSystem.shared.logWarning(.pipeline, "Terms of service not accepted - stopping pipeline", sessionId: sessionId)
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowOnboarding"),
                    object: nil
                )
                self.delegate?.pipeline(self, didFail: APIError.termsRequired)
                return  // Stop here - don't make LLM request
            } catch {
                // Don't block on API errors - log and continue
                // Network issues shouldn't prevent the user from using the app
                LoggingManager.shared.error(.generic, "Failed to track usage: \(error)")
            }

            // Start dev-mode logging
            let logID = DevLogger.shared.start(prompt: "mode=\(self.mode.rawValue), query=\(cleanedDraft)")

            do {
                if cancellationFlag { throw PipelineError.cancelled }

                // Stream from /compose API endpoint
                // API handles prompt building, routing, and AI provider selection
                LoggingManager.shared.info(.pipeline, "Using /compose endpoint for \(self.mode.rawValue) mode")

                let stream = try await ComposeClient.shared.stream(
                    mode: self.mode,
                    query: cleanedDraft,
                    appInfo: enhancedContext.appInfo,
                    contextText: contextText,
                    screenshot: shot?.image,
                    tone: finalTone,
                    onGroundingMetadata: { [weak self] metadata in
                        guard let self = self else { return }
                        self.delegate?.pipeline(self, didReceiveGroundingMetadata: metadata)
                    }
                )

                LoggingManager.shared.info(.pipeline, "Stream created, waiting for tokens...")
                var fullReply = ""
                for try await token in stream {
                    if cancellationFlag { throw PipelineError.cancelled }
                    fullReply += token
                    delegate?.pipeline(self, didReceive: token)
                    DevLogger.shared.append(token: token, to: logID)
                }

                if fullReply.isEmpty {
                    LoggingManager.shared.info(.pipeline, "Stream completed but no tokens received")
                }

                // 4. Insert reply back & notify delegate.
                DevLogger.shared.finish(reply: fullReply, for: logID)
                LoggingManager.shared.info(
                    .pipeline, "Final reply length=\(fullReply.count); content:\n\(fullReply)")
                // Only paste if not in 'ask' mode and auto-insert is enabled
                if self.mode != .ask && self.autoInsertText {
                    try FocusManager.shared.insertReplyAndRestoreFocus(fullReply)
                }
                // Pipeline completed successfully
                LoggingSystem.shared.logInfo(.pipeline, "Pipeline execution completed successfully", sessionId: sessionId, metadata: [
                    "reply_length": AnyCodable(fullReply.count)
                ])
                LoggingSystem.shared.endSession(outcome: .success)
                delegate?.pipeline(self, didComplete: fullReply)

            } catch {
                // Determine failure type for better session tracking
                let outcome: SessionOutcome
                if let composeError = error as? ComposeClient.ComposeError {
                    switch composeError {
                    case .httpError(let status, let body):
                        if status == 429 && body?.contains("quota") == true {
                            outcome = .quotaExceeded
                        } else {
                            outcome = .error
                        }
                    default:
                        outcome = .error
                    }
                } else if error is PipelineError {
                    outcome = .error
                } else {
                    outcome = .error
                }

                LoggingSystem.shared.logError(.pipeline, error, sessionId: sessionId, metadata: [
                    "pipeline_stage": AnyCodable("execution"),
                    "error_type": AnyCodable(String(describing: Swift.type(of: error)))
                ])
                LoggingSystem.shared.endSession(outcome: outcome)

                DevLogger.shared.finish(reply: "[ERROR: \(error)]", for: logID)
                delegate?.pipeline(self, didFail: error)
            }

        } catch {
            delegate?.pipeline(self, didFail: error)
        }
    }
}
