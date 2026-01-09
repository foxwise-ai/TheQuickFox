//
//  StoreLogger.swift
//  TheQuickFox
//
//  Logging system for store actions and state changes
//

import Foundation

// MARK: - Store Logger Protocol

protocol StoreLogger {
    func logAction(_ action: AppAction, state: AppState)
    func logStateChange(from oldState: AppState, to newState: AppState, action: AppAction)
}

// MARK: - Console Store Logger

final class ConsoleStoreLogger: StoreLogger {

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func logAction(_ action: AppAction, state: AppState) {
        let timestamp = dateFormatter.string(from: Date())
        let actionDescription = describe(action)
        print("🔄 [\(timestamp)] ACTION: \(actionDescription)")
    }

    func logStateChange(from oldState: AppState, to newState: AppState, action: AppAction) {
        let timestamp = dateFormatter.string(from: Date())
        let changes = detectChanges(from: oldState, to: newState)

        if !changes.isEmpty {
            print("📊 [\(timestamp)] STATE CHANGES:")
            for change in changes {
                print("   \(change)")
            }
        }
    }

    // MARK: - Private Methods

    private func describe(_ action: AppAction) -> String {
        switch action {
        case .hud(let hudAction):
            return "HUD.\(describe(hudAction))"
        case .history(let historyAction):
            return "HISTORY.\(describe(historyAction))"
        case .session(let sessionAction):
            return "SESSION.\(describe(sessionAction))"
        case .subscription(let subscriptionAction):
            return "SUBSCRIPTION.\(describe(subscriptionAction))"
        case .toast(let toastAction):
            return "TOAST.\(describe(toastAction))"
        case .metrics(let metricsAction):
            return "METRICS.\(describe(metricsAction))"
        }
    }

    private func describe(_ action: HUDAction) -> String {
        switch action {
        case .prepareWindow: return "prepareWindow"
        case .showWindow: return "showWindow"
        case .hide: return "hide"
        case .hideForReactivation: return "hideForReactivation"
        case .hideWithReason(let reason): return "hideWithReason(\(reason))"
        case .animateToHUD: return "animateToHUD"
        case .changeMode(let mode): return "changeMode(\(mode))"
        case .changeTone(let tone): return "changeTone(\(tone))"
        case .updateQuery(let query): return "updateQuery(\(query.prefix(20))...)"
        case .submitQuery(let query): return "submitQuery(\(query.prefix(20))...)"
        case .clearQuery: return "clearQuery"
        case .startProcessing(let query, _): return "startProcessing(\(query.prefix(20))...)"
        case .receiveResponseToken(let token): return "receiveResponseToken(\(token.prefix(10))...)"
        case .receiveGroundingMetadata(let metadata): return "receiveGroundingMetadata(supports: \(metadata.groundingSupports?.count ?? 0))"
        case .completeProcessing(let query, _): return "completeProcessing(\(query.prefix(20))...)"
        case .failProcessing(let error): return "failProcessing(\(error))"
        case .setLoaderVisible(let visible): return "setLoaderVisible(\(visible))"
        case .setResponseContainerVisible(let visible): return "setResponseContainerVisible(\(visible))"
        case .setPanelHeight(let height): return "setPanelHeight(\(height))"
        case .setTextEditable(let editable): return "setTextEditable(\(editable))"
        case .setBorderAnimation(let active): return "setBorderAnimation(\(active))"
        case .resetAnimateToHUD: return "resetAnimateToHUD"
        case .setCanRespond(let canRespond): return "setCanRespond(\(canRespond))"
        case .navigateHistoryUp: return "navigateHistoryUp"
        case .navigateHistoryDown: return "navigateHistoryDown"
        case .restoreFromHistory(let index): return "restoreFromHistory(\(index))"
        case .saveDraft: return "saveDraft"
        case .markResponseUsed: return "markResponseUsed"
        case .activeWindowChanged: return "activeWindowChanged"
        }
    }

    private func describe(_ action: HistoryAction) -> String {
        switch action {
        case .addEntry: return "addEntry"
        case .selectEntry: return "selectEntry"
        case .updateSearch(let query): return "updateSearch(\(query))"
        case .deleteEntry: return "deleteEntry"
        case .clearAll: return "clearAll"
        case .updateEntryTitle: return "updateEntryTitle"
        }
    }

    private func describe(_ action: SessionAction) -> String {
        switch action {
        case .start(let mode, let tone, _, let isDemoMode): return "start(\(mode), \(tone), demo:\(isDemoMode))"
        case .restore: return "restore"
        case .end: return "end"
        case .updateScreenshot: return "updateScreenshot"
        case .addToQueryHistory: return "addToQueryHistory"
        case .updateDraft: return "updateDraft"
        case .markRestorable(let restorable): return "markRestorable(\(restorable))"
        case .endWithReason(let reason): return "endWithReason(\(reason))"
        case .setCloseReason(let reason): return "setCloseReason(\(reason))"
        case .markResponseUsed(let used): return "markResponseUsed(\(used))"
        case .setCurrentQuery(let query): return "setCurrentQuery(\(query.prefix(20))...)"
        case .setCurrentResponse: return "setCurrentResponse"
        case .startProcessing: return "startProcessing"
        case .stopProcessing: return "stopProcessing"
        case .updateResponseBuffer: return "updateResponseBuffer"
        case .setProcessingMode(let mode): return "setProcessingMode(\(mode))"
        case .setProcessingTone(let tone): return "setProcessingTone(\(tone))"
        }
    }

    private func describe(_ action: SubscriptionAction) -> String {
        switch action {
        case .startFetch: return "startFetch"
        case .updateFromDeviceRegistration: return "updateFromDeviceRegistration"
        case .updateFromUsageStatus: return "updateFromUsageStatus"
        case .fetchComplete: return "fetchComplete"
        case .fetchError(let error): return "fetchError(\(error))"
        }
    }

    private func describe(_ action: ToastAction) -> String {
        switch action {
        case .show(let reason, _, let appName, _, _): return "show(\(reason.shortMessage), app:\(appName))"
        case .hide: return "hide"
        }
    }

    private func describe(_ action: MetricsAction) -> String {
        switch action {
        case .startFetch(let timeRange): return "startFetch(\(timeRange))"
        case .updateData: return "updateData"
        case .fetchComplete: return "fetchComplete"
        case .fetchError(let error): return "fetchError(\(error))"
        case .incrementQueryCount: return "incrementQueryCount"
        case .resetQueryCount: return "resetQueryCount"
        case .showInHUD: return "showInHUD"
        case .hideFromHUD: return "hideFromHUD"
        }
    }

    private func detectChanges(from oldState: AppState, to newState: AppState) -> [String] {
        var changes: [String] = []

        // HUD changes
        if oldState.hud.isVisible != newState.hud.isVisible {
            changes.append("hud.isVisible: \(oldState.hud.isVisible) → \(newState.hud.isVisible)")
        }
        if oldState.hud.mode != newState.hud.mode {
            changes.append("hud.mode: \(oldState.hud.mode) → \(newState.hud.mode)")
        }
        if oldState.hud.processing != newState.hud.processing {
            changes.append("hud.processing: \(oldState.hud.processing) → \(newState.hud.processing)")
        }
        if oldState.hud.response != newState.hud.response {
            changes.append("hud.response: \(describe(oldState.hud.response)) → \(describe(newState.hud.response))")
        }
        if oldState.hud.ui != newState.hud.ui {
            changes.append("hud.ui: \(describe(oldState.hud.ui)) → \(describe(newState.hud.ui))")
        }

        // Session changes
        if oldState.session.isActive != newState.session.isActive {
            changes.append("session.isActive: \(oldState.session.isActive) → \(newState.session.isActive)")
        }
        if oldState.session.canRestore != newState.session.canRestore {
            changes.append("session.canRestore: \(oldState.session.canRestore) → \(newState.session.canRestore)")
        }

        // History changes
        if oldState.history.entries.count != newState.history.entries.count {
            changes.append("history.entries.count: \(oldState.history.entries.count) → \(newState.history.entries.count)")
        }

        return changes
    }

    private func describe(_ response: ResponseState) -> String {
        switch response {
        case .idle: return "idle"
        case .streaming(let content): return "streaming(\(content.count) chars)"
        case .completed(let content): return "completed(\(content.count) chars)"
        case .failed(let error): return "failed(\(error))"
        }
    }

    private func describe(_ ui: HUDUIState) -> String {
        return "UI(h:\(ui.panelHeight), edit:\(ui.textIsEditable), loader:\(ui.loaderIsVisible))"
    }
}

// MARK: - Silent Logger (for production)

final class SilentStoreLogger: StoreLogger {
    func logAction(_ action: AppAction, state: AppState) {
        // No-op
    }

    func logStateChange(from oldState: AppState, to newState: AppState, action: AppAction) {
        // No-op
    }
}
