//
//  AppReducer.swift
//  TheQuickFox
//
//  Main reducer that coordinates all state changes
//

import Foundation

// MARK: - Main App Reducer

func appReducer(_ state: AppState, _ action: AppAction) -> AppState {
    var newState = state

    switch action {
    case .hud(let hudAction):
        newState.hud = hudReducer(state.hud, hudAction)

    case .history(let historyAction):
        newState.history = historyReducer(state.history, historyAction)

    case .session(let sessionAction):
        newState.session = sessionReducer(state.session, sessionAction)

    case .subscription(let subscriptionAction):
        newState.subscription = subscriptionReducer(state.subscription, subscriptionAction)

    case .toast(let toastAction):
        newState.toast = toastReducer(state.toast, toastAction)

    case .metrics(let metricsAction):
        newState.metrics = metricsReducer(state.metrics, metricsAction)
    }

    // Apply cross-cutting logic
    newState = applyCrossCuttingLogic(newState, action)

    return newState
}

// MARK: - Cross-Cutting Logic

private func applyCrossCuttingLogic(_ state: AppState, _ action: AppAction) -> AppState {
    var newState = state

    // Intent-based session restore capability
    switch action {
    case .hud(.startProcessing), .hud(.receiveResponseToken):
        // Always restore when processing (user didn't intend to lose progress)
        newState.session.canRestore = true

    case .hud(.completeProcessing), .hud(.failProcessing):
        // Keep restorable for ask mode with responses (useful to see results again)
        newState.session.canRestore = (newState.hud.mode == .ask)

    case .hud(.hide):
        // Old generic hide - treat as unintentional (default .unknown reason)
        newState.session.lastCloseReason = .unknown
        newState.session.canRestore = shouldRestoreSession(
            newState: newState,
            closeReason: .unknown
        )

    case .hud(.hideWithReason(let reason)):
        // New intent-aware hide with explicit reason
        newState.session.lastCloseReason = reason
        newState.session.canRestore = shouldRestoreSession(
            newState: newState,
            closeReason: reason
        )

    case .hud(.markResponseUsed):
        // User successfully used the response - mark for intentional close
        newState.session.responseWasUsed = true

    case .session(.end), .session(.endWithReason):
        // Explicit session end - never restore
        newState.session.canRestore = false
        newState.session.responseWasUsed = false

    case .session(.setCloseReason(let reason)):
        newState.session.lastCloseReason = reason

    case .session(.markResponseUsed(let used)):
        newState.session.responseWasUsed = used

    case .session(.start(let mode, let tone, _, let demoPageContext)):
        // Clear HUD content when starting fresh session
        print("🎯 Session start - demoPageContext: \(demoPageContext ?? "nil")")
        if let demoPage = demoPageContext {
            // Demo mode - prefill query based on page
            switch demoPage {
            case "support":
                // Support page - dynamic date query
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                let futureDate =
                    Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()
                let dateString = formatter.string(from: futureDate)
                newState.hud.currentQuery = "Cancels \(dateString). Feedback?"
                print("📝 Prefilled support query: \(newState.hud.currentQuery)")
            case "logo":
                // Logo page - feedback query
                newState.hud.currentQuery =
                    "Give me some feedback for my logo for my pet ride sharing service"
                print("📝 Prefilled logo query: \(newState.hud.currentQuery)")
            default:
                newState.hud.currentQuery = ""
                print("📝 No prefill for context: \(demoPage)")
            }
        } else {
            newState.hud.currentQuery = ""
            print("📝 No demo context - clearing query")
        }
        newState.hud.response = .idle
        // Reset UI to initial collapsed state
        newState.hud.ui = .initial
        // Sync HUD mode and tone with session
        newState.hud.mode = mode
        newState.hud.tone = tone
        
    case .session(.restore):
        // Session restoration - preserve all HUD state
        print("📝 Restoring session - preserving existing HUD state")

    default:
        break
    }

    return newState
}

/// Determines whether a session should be restored based on close reason and current state
private func shouldRestoreSession(newState: AppState, closeReason: HUDCloseReason) -> Bool {
    // Always restore if currently processing (loading states)
    if newState.hud.processing != .idle {
        return true
    }

    // Check if response was used (indicates successful completion)
    if newState.session.responseWasUsed {
        return false  // User successfully used response, don't restore
    }

    // Check close reason intent
    if closeReason.isIntentional {
        return false  // User intentionally closed, don't restore
    }

    // For unintentional closes, restore if there's valuable content
    let hasCompletedResponse = {
        switch newState.hud.response {
        case .completed: return true
        default: return false
        }
    }()

    let hasContent = !newState.hud.currentQuery.isEmpty || hasCompletedResponse

    // Restore for Ask mode with content, or any mode with processing
    return newState.hud.mode == .ask && hasContent
}
