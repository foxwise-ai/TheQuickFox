//
//  SessionReducer.swift
//  TheQuickFox
//
//  Pure functions for session state transitions
//

import Foundation

func sessionReducer(_ state: SessionState, _ action: SessionAction) -> SessionState {
    var newState = state

    switch action {
    case .start(let mode, let tone, let screenshot, let demoPageContext):
        newState.isActive = true
        // Only update screenshot if provided, otherwise keep existing (for demo mode)
        if screenshot != nil {
            newState.cachedScreenshot = screenshot
        }
        newState.canRestore = false
        newState.currentDraft = ""
        // Set session mode and tone
        newState.currentMode = mode
        newState.currentTone = tone
        // Reset processing state
        newState.currentResponse = ""
        newState.responseBuffer = ""
        newState.isProcessing = false
        newState.pipeline = nil
        // Set demo page context
        newState.demoPageContext = demoPageContext
        
    case .restore:
        // Restore a session that was unintentionally closed
        // Keep all existing state but mark as active
        newState.isActive = true
        newState.canRestore = false  // No longer restorable once restored

    case .end:
        newState.isActive = false
        newState.canRestore = false
        newState.cachedScreenshot = nil
        newState.currentDraft = ""

    case .updateScreenshot(let screenshot):
        newState.cachedScreenshot = screenshot

    case .addToQueryHistory(let query):
        // Don't add empty queries or duplicates of the last entry
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, newState.queryHistory.last != trimmed else {
            return newState
        }

        newState.queryHistory.append(trimmed)
        newState.historyIndex = -1 // Reset to current draft
        newState.currentDraft = ""

    case .updateDraft(let draft):
        if newState.historyIndex == -1 {
            newState.currentDraft = draft
        }

    case .markRestorable(let restorable):
        newState.canRestore = restorable

    case .endWithReason(let reason):
        newState.isActive = false
        newState.canRestore = false
        newState.cachedScreenshot = nil
        newState.currentDraft = ""
        newState.lastCloseReason = reason
        newState.responseWasUsed = false

    case .setCloseReason(let reason):
        newState.lastCloseReason = reason

    case .markResponseUsed(let used):
        newState.responseWasUsed = used

    // Migrated from HUDSessionState actions
    case .setCurrentQuery(let query):
        newState.currentQuery = query

    case .setCurrentResponse(let response):
        newState.currentResponse = response

    case .startProcessing(let pipeline):
        newState.isProcessing = true
        newState.pipeline = pipeline
        newState.responseBuffer = ""

    case .stopProcessing:
        newState.isProcessing = false
        newState.pipeline = nil

    case .updateResponseBuffer(let content):
        newState.responseBuffer = content

    case .setProcessingMode(let mode):
        newState.currentMode = mode

    case .setProcessingTone(let tone):
        newState.currentTone = tone
    }

    return newState
}

// MARK: - History Navigation Helpers

extension SessionState {
    func navigateUp() -> (newState: SessionState, queryText: String) {
        var newState = self
        var queryText = ""

        if historyIndex == -1 {
            // Save current draft before entering history
            newState.currentDraft = currentDraft

            // Move to most recent history entry
            if !queryHistory.isEmpty {
                newState.historyIndex = queryHistory.count - 1
                queryText = queryHistory[newState.historyIndex]
            }
        } else if historyIndex > 0 {
            // Move to older entry
            newState.historyIndex -= 1
            queryText = queryHistory[newState.historyIndex]
        } else {
            // Already at oldest entry
            queryText = queryHistory[historyIndex]
        }

        return (newState, queryText)
    }

    func navigateDown() -> (newState: SessionState, queryText: String) {
        var newState = self
        var queryText = ""

        if historyIndex >= 0 {
            if historyIndex < queryHistory.count - 1 {
                // Move to newer entry
                newState.historyIndex += 1
                queryText = queryHistory[newState.historyIndex]
            } else {
                // Return to current draft
                newState.historyIndex = -1
                queryText = currentDraft
            }
        } else {
            // Already at current draft
            queryText = currentDraft
        }

        return (newState, queryText)
    }
}
