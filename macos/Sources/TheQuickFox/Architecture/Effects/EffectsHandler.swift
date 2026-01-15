//
//  EffectsHandler.swift
//  TheQuickFox
//
//  Handles side effects (API calls, file operations, etc.) outside of reducers
//

import Foundation
import Cocoa

// MARK: - Effects Handler Protocol

protocol EffectsHandler {
    func handle(action: AppAction, state: AppState, dispatch: @escaping (AppAction) -> Void)
    func setDispatchFunction(_ dispatch: @escaping (AppAction) -> Void)
}

// MARK: - Default Effects Handler

final class DefaultEffectsHandler: EffectsHandler {

    // MARK: - Dependencies

    private let screenshotService: ScreenshotService
    private let pipelineService: PipelineService
    private let focusService: FocusService
    private let windowService: WindowService
    private let historyService: HistoryService

    // MARK: - Internal State

    private var dispatch: ((AppAction) -> Void)?
    private var demoPageContext: String? = nil

    // MARK: - Active Window Monitoring

    private var activeWindowMonitor: Any?  // NSWorkspace notification observer
    private var originalWindowPID: pid_t?  // PID of the window that was active when HUD opened

    // MARK: - Initialization

    init(
        screenshotService: ScreenshotService = DefaultScreenshotService(),
        pipelineService: PipelineService = DefaultPipelineService(),
        focusService: FocusService = DefaultFocusService(),
        windowService: WindowService = DefaultWindowService(),
        historyService: HistoryService = DefaultHistoryService()
    ) {
        self.screenshotService = screenshotService
        self.pipelineService = pipelineService
        self.focusService = focusService
        self.windowService = windowService
        self.historyService = historyService
    }

    // MARK: - EffectsHandler Implementation

    func setDispatchFunction(_ dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
    }

    func handle(action: AppAction, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        switch action {
        case .hud(let hudAction):
            handleHUDEffects(hudAction, state: state, dispatch: dispatch)

        case .history(let historyAction):
            handleHistoryEffects(historyAction, state: state, dispatch: dispatch)

        case .session(let sessionAction):
            handleSessionEffects(sessionAction, state: state, dispatch: dispatch)

        case .subscription(let subscriptionAction):
            handleSubscriptionEffects(subscriptionAction, state: state, dispatch: dispatch)

        case .toast:
            // No side effects needed - ToastManager handles state changes via Combine
            break

        case .metrics(let metricsAction):
            handleMetricsEffects(metricsAction, state: state, dispatch: dispatch)
        }
    }

    // MARK: - HUD Effects

    private func handleHUDEffects(_ action: HUDAction, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        switch action {
        case .prepareWindow:
            handlePrepareWindow(state: state, dispatch: dispatch)

        case .showWindow:
            // Start monitoring for active window changes when HUD becomes visible
            startActiveWindowMonitoring(state: state, dispatch: dispatch)

        case .hide, .hideWithReason:
            handleHideHUD(state: state, dispatch: dispatch)
            // Stop monitoring when HUD is hidden
            stopActiveWindowMonitoring()

        case .hideForReactivation:
            // Don't clean up window highlight for reactivation, but do stop monitoring
            // (it will restart when HUD is shown again)
            stopActiveWindowMonitoring()

        case .submitQuery(let query):
            handleSubmitQuery(query, state: state, dispatch: dispatch)

        case .completeProcessing(let query, let response):
            handleCompleteProcessing(query: query, response: response, state: state, dispatch: dispatch)

        case .navigateHistoryUp:
            handleNavigateHistoryUp(state: state, dispatch: dispatch)

        case .navigateHistoryDown:
            handleNavigateHistoryDown(state: state, dispatch: dispatch)

        case .activeWindowChanged:
            handleActiveWindowChanged(state: state, dispatch: dispatch)

        default:
            break
        }
    }

    private func handlePrepareWindow(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Capture focus for later restoration and check if text input is available
        let canRespond: Bool
        if let demoPage = state.session.demoPageContext {
            // Store demo page context for later
            self.demoPageContext = demoPage

            // Different behavior based on demo page
            if demoPage == "logo" {
                // Logo page - Compose mode not available
                canRespond = false
            } else {
                // Support page - Compose mode available
                canRespond = true
            }
        } else {
            canRespond = focusService.captureCurrentFocus()
            self.demoPageContext = nil
        }
        dispatch(.hud(.setCanRespond(canRespond)))

        // Intel Macs: Skip animation entirely for fastest HUD launch
        // Apple Silicon: Run the animate-to-HUD effect
        print("🏛️ ArchitectureDetector.isIntelMac = \(ArchitectureDetector.isIntelMac)")
        if ArchitectureDetector.isIntelMac {
            dispatch(.hud(.showWindow))
        } else {
            // Start animation immediately, but don't show HUD yet
            dispatch(.hud(.animateToHUD))

            // Show HUD after animation completes (animateToHUD is 0.3s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dispatch(.hud(.showWindow))
            }
        }
    }

    private func handleHideHUD(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Clean up any remaining window highlighting when HUD is hidden
        WindowHighlighter.shared.forceHideHighlight()
    }

    private func handleSubmitQuery(_ query: String, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Add to session history
        dispatch(.session(.addToQueryHistory(query)))

        // Log screenshot status
        print("🔍 handleSubmitQuery - cachedScreenshot: \(state.session.cachedScreenshot != nil)")
        if let screenshot = state.session.cachedScreenshot {
            print("🔍 Screenshot details - app: \(screenshot.activeInfo.appName ?? "nil"), size: \(screenshot.image.size)")
        }

        // Start processing
        dispatch(.hud(.startProcessing(query: query, screenshot: state.session.cachedScreenshot)))

        // Start the AI pipeline
        pipelineService.startProcessing(
            query: query,
            mode: state.hud.mode,
            tone: state.hud.tone,
            screenshot: state.session.cachedScreenshot,
            isDemoMode: state.session.demoPageContext != nil
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .token(let token):
                    dispatch(.hud(.receiveResponseToken(token)))

                case .completion(let response):
                    // Extract query from processing state before dispatching completeProcessing
                    // Note: We need to capture the query BEFORE the action is dispatched,
                    // because the reducer will set processing to .idle
                    let currentState = state
                    let query: String
                    if case .active(let pipeline) = currentState.hud.processing {
                        query = pipeline.query
                    } else {
                        query = currentState.hud.currentQuery
                    }
                    dispatch(.hud(.completeProcessing(query: query, response: response)))

                case .groundingMetadata(let metadata):
                    dispatch(.hud(.receiveGroundingMetadata(metadata)))

                case .error(let error):
                    // Handle specific pipeline errors
                    if let pipelineError = error as? PromptPipeline.PipelineError {
                        switch pipelineError {
                        case .screenshotUnavailable:
                            dispatch(.hud(.failProcessing(error: error.localizedDescription)))
                            dispatch(.hud(.hide))
                        default:
                            // Generic pipeline error - show user-friendly alert
                            dispatch(.hud(.failProcessing(error: "Request failed - please try again")))
                            dispatch(.hud(.hide))
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Request Failed"
                                alert.informativeText = "Something went wrong with your request. Please try again. If the issue persists, contact support."
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                                // Show the HUD again so user can retry
                                dispatch(.hud(.showWindow))
                            }
                        }
                    } else if let apiError = error as? APIError {
                        // Handle API errors
                        switch apiError {
                        case .termsRequired:
                            // Terms of service not accepted - onboarding already triggered by pipeline
                            dispatch(.hud(.failProcessing(error: "Terms of service required")))
                            dispatch(.hud(.hide))
                        case .quotaExceeded:
                            // Already handled by pipeline notification, just hide HUD
                            dispatch(.hud(.failProcessing(error: "Trial quota exceeded")))
                            dispatch(.hud(.hide))
                        default:
                            // Other API errors - show generic message
                            dispatch(.hud(.failProcessing(error: "Request failed - please try again")))
                            dispatch(.hud(.hide))
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Request Failed"
                                alert.informativeText = "Something went wrong with your request. Please try again. If the issue persists, contact support."
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                                // Show the HUD again so user can retry
                                dispatch(.hud(.showWindow))
                            }
                        }
                    } else if let composeError = error as? ComposeClient.ComposeError {
                        // Handle Compose API errors
                        switch composeError {
                        case .connectionFailed:
                            // Reset HUD state and temporarily hide for modal
                            dispatch(.hud(.failProcessing(error: "Connection failed - please try again")))
                            dispatch(.hud(.hide)) // Simple hide, don't end session
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Unable to Connect"
                                alert.informativeText = composeError.errorDescription ?? "Unable to connect to TheQuickFox servers. Please check your internet connection."
                                alert.alertStyle = .critical
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                                // Just show the window again - session remains active
                                dispatch(.hud(.showWindow))
                            }
                        case .authTokenMissing:
                            // Reset HUD state and hide
                            dispatch(.hud(.failProcessing(error: "Authentication failed")))
                            dispatch(.hud(.hide))
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Authentication Failed"
                                alert.informativeText = composeError.errorDescription ?? "Authentication failed. Please restart the app."
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        case .httpError(let status, _):
                            if status == 401 {
                                // Invalid API key
                                dispatch(.hud(.failProcessing(error: "Invalid API key")))
                                dispatch(.hud(.hide))
                                DispatchQueue.main.async {
                                    let alert = NSAlert()
                                    alert.messageText = "Authentication Error"
                                    alert.informativeText = "Authentication failed. Please restart the app."
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                }
                            } else if status == 403 {
                                // Access denied - likely subscription status changed
                                dispatch(.hud(.failProcessing(error: "Access denied")))
                                dispatch(.hud(.hide))
                                DispatchQueue.main.async {
                                    let alert = NSAlert()
                                    alert.messageText = "Access Denied"
                                    alert.informativeText = "Your subscription status may have changed. Please quit and restart TheQuickFox."
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "Quit")
                                    alert.addButton(withTitle: "Cancel")

                                    if alert.runModal() == .alertFirstButtonReturn {
                                        NSApplication.shared.terminate(nil)
                                    }
                                }
                            } else if status >= 500 && status < 600 {
                                // Server errors - reset state and temporarily hide for modal
                                dispatch(.hud(.failProcessing(error: "Service unavailable - please try again")))
                                dispatch(.hud(.hide)) // Simple hide, don't end session
                                DispatchQueue.main.async {
                                    let alert = NSAlert()
                                    alert.messageText = "Service Unavailable"
                                    alert.informativeText = composeError.errorDescription ?? "The service is temporarily unavailable. Please try again later."
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                    // Check subscription status before showing HUD again
                                    dispatch(.subscription(.startFetch))
                                    // Show HUD after a brief delay to allow subscription to load
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        dispatch(.hud(.showWindow))
                                    }
                                }
                            } else {
                                // Other HTTP errors can show in response
                                dispatch(.hud(.failProcessing(error: composeError.errorDescription ?? "API Error: \(status)")))
                            }
                        case .invalidResponse:
                            dispatch(.hud(.failProcessing(error: composeError.errorDescription ?? "Invalid API response")))
                        default:
                            dispatch(.hud(.failProcessing(error: composeError.errorDescription ?? error.localizedDescription)))
                        }
                    } else {
                        // Check for NSURLError (network errors)
                        if let urlError = error as? URLError {
                            // Handle network errors - reset state, hide temporarily for modal
                            dispatch(.hud(.failProcessing(error: "Network error - please try again")))
                            dispatch(.hud(.hideWithReason(.clickOutside))) // Unintentional close preserves session
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Network Error"
                                alert.informativeText = urlError.localizedDescription
                                alert.alertStyle = .critical
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                                // Check subscription status before showing HUD again
                                dispatch(.subscription(.startFetch))
                                // Show HUD after a brief delay to allow subscription to load
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    dispatch(.hud(.showWindow))
                                }
                            }
                        } else {
                            // Check error description for wrapped OpenAI errors
                            let errorDescription = error.localizedDescription
                            if errorDescription.contains("httpError(status: 401") || errorDescription.contains("401") {
                                // This is likely an invalid API key error wrapped in another error
                                dispatch(.hud(.failProcessing(error: "Invalid API key")))
                                dispatch(.hud(.hide))
                                DispatchQueue.main.async {
                                    let alert = NSAlert()
                                    alert.messageText = "Invalid OpenAI API Key"
                                    alert.informativeText = "Your API key appears to be invalid or has been revoked. Please update it in Account Settings."
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "Open Account Settings")
                                    alert.addButton(withTitle: "Cancel")
                                    
                                    if alert.runModal() == .alertFirstButtonReturn {
                                        AccountWindowController.show()
                                    }
                                }
                            } else {
                                // Generic error - show user-friendly alert
                                dispatch(.hud(.failProcessing(error: "Request failed - please try again")))
                                dispatch(.hud(.hide))
                                DispatchQueue.main.async {
                                    let alert = NSAlert()
                                    alert.messageText = "Request Failed"
                                    alert.informativeText = "Something went wrong with your request. Please try again. If the issue persists, contact support."
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                    // Show the HUD again so user can retry
                                    dispatch(.hud(.showWindow))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleCompleteProcessing(query: String, response: String, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Query is now passed directly from the action, avoiding the race condition
        print("📚 DEBUG: Creating history entry with query: '\(query)'")

        // Increment query counter for periodic metrics display
        dispatch(.metrics(.incrementQueryCount))

        // Check if we should show metrics celebration
        let updatedCount = state.metrics.queriesSinceLastDisplay + 1
        if updatedCount >= state.metrics.displayFrequency {
            // Show metrics in HUD after this response is handled
            dispatch(.metrics(.showInHUD))
            dispatch(.metrics(.resetQueryCount))
        }

        // Create history entry
        let entry = HistoryEntry(
            query: query,
            response: response,
            mode: state.hud.mode,
            tone: state.hud.tone
        )

        print("📚 DEBUG: Created entry with title: '\(entry.title)'")

        dispatch(.history(.addEntry(entry)))

        print("🔍 DEBUG: handleCompleteProcessing - mode: \(state.hud.mode), canRespond: \(state.hud.canRespond)")

        // For all modes except ask, insert text and close HUD
        if state.hud.mode != .ask {
            // Capture HUD frame BEFORE hiding for potential toast animation
            let capturedHUDFrame = self.windowService.getCurrentHUDFrame()
            print("📐 Captured HUD frame before hiding: \(capturedHUDFrame?.debugDescription ?? "nil")")

            // Hide HUD first to avoid focus conflicts during text insertion
            dispatch(.hud(.hide))

            // Add a small delay to ensure the HUD is hidden before text insertion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.demoPageContext != nil {
                    // In demo mode, insert text into the webview's textarea
                    self.insertTextInDemoMode(response) { success in
                        DispatchQueue.main.async {
                            print("📝 Demo mode text insertion result: \(success)")
                            dispatch(.session(.end))
                        }
                    }
                } else {
                    // Check if no input was selected when HUD was opened
                    if !state.hud.canRespond {
                        print("❌ No input field was selected - showing toast")

                        let appIcon = self.extractAppIcon(from: state.session.cachedScreenshot)
                        let appName = self.extractAppName(from: state.session.cachedScreenshot)

                        dispatch(.toast(.show(
                            reason: .noInputSelected,
                            appIcon: appIcon,
                            appName: appName,
                            responseText: response,
                            hudFrame: capturedHUDFrame
                        )))
                        dispatch(.session(.end))
                        return
                    }

                    // Detect app switch before insertion
                    let originalAppPID = state.session.cachedScreenshot?.activeInfo.pid
                    let currentFrontmostApp = NSWorkspace.shared.frontmostApplication

                    if let originalPID = originalAppPID,
                       let currentApp = currentFrontmostApp,
                       currentApp.processIdentifier != originalPID {
                        print("❌ App switched from PID \(originalPID) to \(currentApp.processIdentifier) - showing toast")

                        let appIcon = self.extractAppIcon(from: state.session.cachedScreenshot)
                        let appName = self.extractAppName(from: state.session.cachedScreenshot)

                        dispatch(.toast(.show(
                            reason: .appSwitched,
                            appIcon: appIcon,
                            appName: appName,
                            responseText: response,
                            hudFrame: capturedHUDFrame
                        )))
                        dispatch(.session(.end))
                        return
                    }

                    // Attempt text insertion
                    self.focusService.insertTextAndRestoreFocus(response) { failureReason in
                        DispatchQueue.main.async {
                            if let reason = failureReason {
                                print("❌ Text insertion failed with reason: \(reason) - showing toast")

                                // Extract app info from cached screenshot
                                let appIcon = self.extractAppIcon(from: state.session.cachedScreenshot)
                                let appName = self.extractAppName(from: state.session.cachedScreenshot)

                                // Show toast notification with specific failure reason
                                dispatch(.toast(.show(
                                    reason: reason,
                                    appIcon: appIcon,
                                    appName: appName,
                                    responseText: response,
                                    hudFrame: capturedHUDFrame
                                )))

                                // Still end session (HUD stays closed)
                                dispatch(.session(.end))
                            } else {
                                print("📝 Text insertion succeeded")
                                dispatch(.session(.end))
                            }
                        }
                    }
                }
            }
        } else {
            // For Ask mode, HUD stays visible but we still need to clean up the window highlight/backdrop
            WindowHighlighter.shared.forceHideHighlight()
        }

        // Generate title asynchronously
        generateTitleForEntry(entry, dispatch: dispatch)
    }

    private func handleNavigateHistoryUp(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        let (newSessionState, queryText) = state.session.navigateUp()
        dispatch(.session(.updateDraft(queryText)))
        dispatch(.hud(.updateQuery(queryText)))
        // Session state will be updated by the cross-cutting logic
    }

    private func handleNavigateHistoryDown(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        let (newSessionState, queryText) = state.session.navigateDown()
        dispatch(.session(.updateDraft(queryText)))
        dispatch(.hud(.updateQuery(queryText)))
        // Session state will be updated by the cross-cutting logic
    }

    // MARK: - History Effects

    private func handleHistoryEffects(_ action: HistoryAction, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        switch action {
        case .addEntry(let entry):
            historyService.saveEntry(entry)

        case .deleteEntry(let id):
            historyService.deleteEntry(id)

        case .clearAll:
            historyService.clearAll()

        case .updateEntryTitle(let id, let title):
            historyService.updateEntryTitle(id, title: title)

        default:
            break
        }
    }

    // MARK: - Session Effects

    private func handleSessionEffects(_ action: SessionAction, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Most session actions don't need side effects
        // They're handled purely in the reducer
    }

    // MARK: - Subscription Effects

    private func handleSubscriptionEffects(_ action: SubscriptionAction, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        switch action {
        case .startFetch:
            // Fetch subscription status from API
            Task {
                do {
                    let usageStatus = try await APIClient.shared.getUsageStatus()
                    await MainActor.run {
                        dispatch(.subscription(.updateFromUsageStatus(usageStatus)))
                        // Update the legacy UserSubscriptionManager for backward compatibility
                        UserSubscriptionManager.shared.updateFromUsageStatus(usageStatus)
                    }
                } catch {
                    await MainActor.run {
                        dispatch(.subscription(.fetchError(error.localizedDescription)))
                    }
                }
            }

        default:
            // Other subscription actions are handled purely in the reducer
            break
        }
    }

    // MARK: - Metrics Effects

    private func handleMetricsEffects(_ action: MetricsAction, state: AppState, dispatch: @escaping (AppAction) -> Void) {
        switch action {
        case .startFetch(let timeRange):
            // Fetch analytics metrics from API
            Task {
                do {
                    let metricsResponse = try await APIClient.shared.getAnalyticsMetrics(timeRange: timeRange)
                    await MainActor.run {
                        dispatch(.metrics(.updateData(metricsResponse.data)))
                        dispatch(.metrics(.fetchComplete))
                    }
                } catch {
                    await MainActor.run {
                        dispatch(.metrics(.fetchError(error.localizedDescription)))
                    }
                }
            }

        case .showInHUD:
            // If we already have data, reducer will show immediately
            // Otherwise fetch data first, then show
            if state.metrics.data == nil {
                Task {
                    do {
                        let metricsResponse = try await APIClient.shared.getAnalyticsMetrics(timeRange: "30d")
                        await MainActor.run {
                            dispatch(.metrics(.updateData(metricsResponse.data)))
                            dispatch(.metrics(.showInHUD))  // Now data exists, so it will show
                        }
                    } catch {
                        print("Failed to fetch metrics for HUD display: \(error)")
                    }
                }
            }

        default:
            // Other metrics actions are handled purely in the reducer
            break
        }
    }

    // MARK: - Helper Methods

    private func generateTitleForEntry(_ entry: HistoryEntry, dispatch: @escaping (AppAction) -> Void) {
        // Create a concise prompt for title generation
        let titlePrompt = """
Based on this user query and AI response, generate a concise title with emoji:

User Query: "\(entry.query)"
AI Response: "\(String(entry.response.prefix(200)))\(entry.response.count > 200 ? "..." : "")"

Return ONLY a title in this format: "[emoji] [concise title]"
Examples:
- 🌙 Intercom response to Kevin
- 💼 Email to boss about vacation
- 🐛 JavaScript error fix
- 📝 Meeting notes summary
- 💬 Quick question answer

Title:
"""

        // Use a direct API call for title generation (no OCR/screenshot needed)
        Task.detached(priority: .utility) {
            do {
                let title = try await self.generateTitleWithOpenAI(prompt: titlePrompt)
                await MainActor.run {
                    dispatch(.history(.updateEntryTitle(entry.id, title)))
                }
            } catch {
                print("❌ Title generation failed: \(error)")
                // Keep the temporary title if generation fails
            }
        }
    }

    // MARK: - Direct API Title Generation

    private func generateTitleWithOpenAI(prompt: String) async throws -> String {
        // Use proxy endpoint (same as main pipeline)
        let baseURL: String = {
            #if LOCAL_API || DEBUG
            return "http://localhost:4003/api/v1"
            #else
            return "https://api.thequickfox.ai/api/v1"
            #endif
        }()

        let url = URL(string: "\(baseURL)/title")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10 // Quick timeout for titles

        // Get auth token
        guard let authToken = try? KeychainManager.shared.getAuthToken() else {
            throw NSError(domain: "TitleGeneration", code: 401, userInfo: [NSLocalizedDescriptionKey: "Auth token missing"])
        }

        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "prompt": prompt
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "HTTP error"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choices = json["choices"] as! [[String: Any]]
        let message = choices[0]["message"] as! [String: Any]
        let content = (message["content"] as! String).trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract clean title (remove quotes, "Title:", etc.)
        let cleanTitle = content
            .replacingOccurrences(of: "Title:", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("✨ Generated title: \(cleanTitle)")
        return cleanTitle
    }

    private func insertTextInDemoMode(_ text: String, completion: @escaping (Bool) -> Void) {
        // Find the onboarding window and its webview
        for window in NSApp.windows {
            if let windowController = window.windowController as? OnboardingWindowController {
                // Insert text into the webview's textarea
                windowController.insertTextIntoReplyField(text) { success in
                    completion(success)
                }
                return
            }
        }

        // If we couldn't find the onboarding window, fail
        print("❌ Could not find onboarding window for demo mode text insertion")
        completion(false)
    }

    // MARK: - App Info Extraction

    private func extractAppIcon(from screenshot: WindowScreenshot?) -> NSImage? {
        guard let screenshot = screenshot else { return nil }

        // Try to get app icon from bundle ID
        if let bundleID = screenshot.activeInfo.bundleID {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }
        }

        // Try to get from app name
        if let appName = screenshot.activeInfo.appName {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }
        }

        return nil
    }

    private func extractAppName(from screenshot: WindowScreenshot?) -> String {
        guard let screenshot = screenshot else { return "" }

        // Prefer app name if available
        if let appName = screenshot.activeInfo.appName {
            return appName
        }

        // Fallback to bundle ID
        if let bundleID = screenshot.activeInfo.bundleID {
            // Extract app name from bundle ID (e.g., "com.apple.Safari" -> "Safari")
            let components = bundleID.split(separator: ".")
            if let lastComponent = components.last {
                return String(lastComponent)
            }
            return bundleID
        }

        return "Unknown App"
    }

    // MARK: - Active Window Monitoring

    /// Start monitoring for active window changes when HUD becomes visible
    private func startActiveWindowMonitoring(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Don't monitor in demo mode
        guard state.session.demoPageContext == nil else { return }

        // Remove any existing observer first
        stopActiveWindowMonitoring()

        // Get the original window PID - try cached screenshot first, then get current frontmost app
        // (Screenshot may not be captured yet since it happens asynchronously)
        if let cachedPID = state.session.cachedScreenshot?.activeInfo.pid {
            originalWindowPID = cachedPID
        } else {
            // Screenshot not ready yet - get PID from current frontmost app (excluding TheQuickFox)
            if let frontmostApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontmostApp.bundleIdentifier,
               !bundleID.contains("TheQuickFox") {
                originalWindowPID = frontmostApp.processIdentifier
            } else {
                // Find the first non-TheQuickFox app in the running apps
                let runningApps = NSWorkspace.shared.runningApplications
                for app in runningApps where app.activationPolicy == .regular {
                    if let bundleID = app.bundleIdentifier, !bundleID.contains("TheQuickFox") {
                        originalWindowPID = app.processIdentifier
                        break
                    }
                }
            }
        }

        // Listen for frontmost app changes
        activeWindowMonitor = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            self.handleActiveWindowChange(notification: notification, dispatch: dispatch)
        }

        print("👁️ Started active window monitoring (original PID: \(originalWindowPID ?? 0))")
    }

    /// Stop monitoring for active window changes
    private func stopActiveWindowMonitoring() {
        if let observer = activeWindowMonitor {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activeWindowMonitor = nil
            print("👁️ Stopped active window monitoring")
        }
        originalWindowPID = nil
    }

    /// Handle when the active application changes
    private func handleActiveWindowChange(notification: Notification, dispatch: @escaping (AppAction) -> Void) {
        // Get the newly activated app
        guard let userInfo = notification.userInfo,
              let activatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // Ignore if TheQuickFox itself became active (user clicked on HUD)
        if let bundleID = activatedApp.bundleIdentifier, bundleID.contains("TheQuickFox") {
            return
        }

        // Check if the app actually changed from the original
        guard let originalPID = originalWindowPID else { return }

        let newPID = activatedApp.processIdentifier
        if newPID != originalPID {
            print("👁️ Active window changed from PID \(originalPID) to \(newPID) (\(activatedApp.localizedName ?? "Unknown"))")
            dispatch(.hud(.activeWindowChanged))
        }
    }

    /// Handle the activeWindowChanged action - reload HUD if in empty state
    private func handleActiveWindowChanged(state: AppState, dispatch: @escaping (AppAction) -> Void) {
        // Check if HUD is in "empty state":
        // 1. HUD is visible
        // 2. User has not typed anything (currentQuery is empty)
        // 3. Not currently processing
        // 4. No response present (for Ask mode: response is idle, or completed but user hasn't interacted)

        guard state.hud.isVisible else { return }
        guard state.hud.currentQuery.isEmpty else {
            print("👁️ Window changed but user has typed - not reloading")
            return
        }
        guard state.hud.processing == .idle else {
            print("👁️ Window changed but processing in progress - not reloading")
            return
        }

        // Check response state
        switch state.hud.response {
        case .idle:
            // Empty state - proceed with reload
            break
        case .streaming, .completed, .failed:
            // Has a response - don't reload
            print("👁️ Window changed but response present - not reloading")
            return
        }

        print("👁️ HUD is in empty state - reloading with new active window")

        // Get the new frontmost app info
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmostApp.bundleIdentifier,
              !bundleID.contains("TheQuickFox") else {
            return
        }

        let isDevelopmentApp = AppCategoryDetector.isDevelopmentApp(
            bundleID: bundleID,
            appName: frontmostApp.localizedName
        )
        let newMode: HUDMode = isDevelopmentApp ? .code : state.hud.mode

        // Update the original PID to the new active window
        originalWindowPID = frontmostApp.processIdentifier

        // Re-capture focus for the new window
        let canRespond = focusService.captureCurrentFocus()
        dispatch(.hud(.setCanRespond(canRespond)))

        // Update mode if app type changed (only if we're in compose/code mode, not ask)
        if state.hud.mode != .ask && state.hud.mode != newMode {
            dispatch(.hud(.changeMode(newMode)))
            print("👁️ Mode changed to \(newMode) based on new app")
        }

        // Capture new screenshot in background
        print("📸 Capturing new screenshot for reloaded HUD...")
        ScreenshotManager.shared.requestCapture { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let screenshot):
                    print("✅ New screenshot captured for window change")
                    dispatch(.session(.updateScreenshot(screenshot)))
                case .failure(let error):
                    print("❌ Screenshot capture failed after window change: \(error)")
                }
            }
        }
    }
}
