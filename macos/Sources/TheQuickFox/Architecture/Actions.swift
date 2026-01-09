//
//  Actions.swift
//  TheQuickFox
//
//  All possible actions that can modify application state
//

import Foundation
import Cocoa

// MARK: - App Actions

enum AppAction {
    // HUD Actions
    case hud(HUDAction)

    // History Actions
    case history(HistoryAction)

    // Session Actions
    case session(SessionAction)

    // Subscription Actions
    case subscription(SubscriptionAction)

    // Toast Actions
    case toast(ToastAction)

    // Metrics Actions
    case metrics(MetricsAction)
}

// MARK: - HUD Actions

enum HUDAction {
    // Window Management
    case prepareWindow  // Starts animation sequence
    case showWindow     // Actually shows the HUD window
    case hide
    case hideForReactivation  // Hide without cleaning up window highlight
    case hideWithReason(HUDCloseReason)  // Hide with explicit close reason
    case animateToHUD

    // Mode and Settings
    case changeMode(HUDMode)
    case changeTone(ResponseTone)

    // Query Processing
    case updateQuery(String)
    case submitQuery(String)
    case clearQuery

    // Response Handling
    case startProcessing(query: String, screenshot: WindowScreenshot?)
    case receiveResponseToken(String)
    case receiveGroundingMetadata(GroundingMetadata)
    case completeProcessing(query: String, response: String)
    case failProcessing(error: String)
    case markResponseUsed  // Track when user successfully uses a response

    // UI State
    case setLoaderVisible(Bool)
    case setResponseContainerVisible(Bool)
    case setPanelHeight(CGFloat)
    case setTextEditable(Bool)
    case setBorderAnimation(Bool)
    case resetAnimateToHUD
    case setCanRespond(Bool)

    // Navigation
    case navigateHistoryUp
    case navigateHistoryDown
    case restoreFromHistory(index: Int)
    case saveDraft(String)

    // Active Window Monitoring
    case activeWindowChanged  // Triggered when user switches to a different app while HUD is visible
}

// Custom Equatable implementation
extension HUDAction: Equatable {
    static func == (lhs: HUDAction, rhs: HUDAction) -> Bool {
        switch (lhs, rhs) {
        case (.prepareWindow, .prepareWindow), (.showWindow, .showWindow), (.hide, .hide), (.hideForReactivation, .hideForReactivation):
            return true
        case (.hideWithReason(let lhsReason), .hideWithReason(let rhsReason)):
            return lhsReason == rhsReason
        case (.markResponseUsed, .markResponseUsed):
            return true
        case (.changeMode(let lhsMode), .changeMode(let rhsMode)):
            return lhsMode == rhsMode
        case (.changeTone(let lhsTone), .changeTone(let rhsTone)):
            return lhsTone == rhsTone
        case (.updateQuery(let lhsQuery), .updateQuery(let rhsQuery)):
            return lhsQuery == rhsQuery
        case (.submitQuery(let lhsQuery), .submitQuery(let rhsQuery)):
            return lhsQuery == rhsQuery
        case (.clearQuery, .clearQuery):
            return true
        case (.startProcessing(let lhsQuery, let lhsScreenshot), .startProcessing(let rhsQuery, let rhsScreenshot)):
            return lhsQuery == rhsQuery && lhsScreenshot?.activeInfo.bundleID == rhsScreenshot?.activeInfo.bundleID
        case (.receiveResponseToken(let lhsToken), .receiveResponseToken(let rhsToken)):
            return lhsToken == rhsToken
        case (.receiveGroundingMetadata, .receiveGroundingMetadata):
            return true  // Don't compare metadata contents for equality
        case (.completeProcessing(let lhsQuery, let lhsResponse), .completeProcessing(let rhsQuery, let rhsResponse)):
            return lhsQuery == rhsQuery && lhsResponse == rhsResponse
        case (.failProcessing(let lhsError), .failProcessing(let rhsError)):
            return lhsError == rhsError
        case (.setLoaderVisible(let lhsVisible), .setLoaderVisible(let rhsVisible)):
            return lhsVisible == rhsVisible
        case (.setResponseContainerVisible(let lhsVisible), .setResponseContainerVisible(let rhsVisible)):
            return lhsVisible == rhsVisible
        case (.setPanelHeight(let lhsHeight), .setPanelHeight(let rhsHeight)):
            return lhsHeight == rhsHeight
        case (.setTextEditable(let lhsEditable), .setTextEditable(let rhsEditable)):
            return lhsEditable == rhsEditable
        case (.setBorderAnimation(let lhsActive), .setBorderAnimation(let rhsActive)):
            return lhsActive == rhsActive
        case (.resetAnimateToHUD, .resetAnimateToHUD):
            return true
        case (.setCanRespond(let lhsCanRespond), .setCanRespond(let rhsCanRespond)):
            return lhsCanRespond == rhsCanRespond
        case (.navigateHistoryUp, .navigateHistoryUp), (.navigateHistoryDown, .navigateHistoryDown):
            return true
        case (.restoreFromHistory(let lhsIndex), .restoreFromHistory(let rhsIndex)):
            return lhsIndex == rhsIndex
        case (.saveDraft(let lhsText), .saveDraft(let rhsText)):
            return lhsText == rhsText
        case (.activeWindowChanged, .activeWindowChanged):
            return true
        default:
            return false
        }
    }
}

// MARK: - History Actions

enum HistoryAction {
    case addEntry(HistoryEntry)
    case selectEntry(HistoryEntry?)
    case updateSearch(String)
    case deleteEntry(UUID)
    case clearAll
    case updateEntryTitle(UUID, String)
}

// MARK: - Session Actions

enum SessionAction {
    case start(mode: HUDMode, tone: ResponseTone, screenshot: WindowScreenshot?, demoPageContext: String? = nil)
    case restore  // Restore an existing session that was unintentionally closed
    case end
    case endWithReason(HUDCloseReason)  // End session with explicit close reason
    case updateScreenshot(WindowScreenshot?)
    case addToQueryHistory(String)
    case updateDraft(String)
    case markRestorable(Bool)
    case setCloseReason(HUDCloseReason)  // Track the last close reason
    case markResponseUsed(Bool)          // Track if response was used

    // Migrated from HUDSessionState actions
    case setCurrentQuery(String)
    case setCurrentResponse(String)
    case startProcessing(pipeline: PromptPipeline)
    case stopProcessing
    case updateResponseBuffer(String)
    case setProcessingMode(HUDMode)
    case setProcessingTone(ResponseTone)
}

// MARK: - Action Helpers

extension AppAction {
    static func showHUD() -> AppAction {
        .hud(.prepareWindow)
    }

    static func hideHUD() -> AppAction {
        .hud(.hide)
    }

    static func submitQuery(_ query: String) -> AppAction {
        .hud(.submitQuery(query))
    }

    static func changeMode(_ mode: HUDMode) -> AppAction {
        .hud(.changeMode(mode))
    }
}

// MARK: - Subscription Actions

enum SubscriptionAction {
    case startFetch
    case updateFromDeviceRegistration(DeviceRegistrationResponse)
    case updateFromUsageStatus(UsageStatusResponse)
    case fetchComplete
    case fetchError(String)
}

// MARK: - Toast Actions

enum ToastAction {
    case show(reason: InsertionFailureReason, appIcon: NSImage?, appName: String, responseText: String, hudFrame: NSRect?)
    case hide
}

// MARK: - Metrics Actions

enum MetricsAction {
    case startFetch(timeRange: String)
    case updateData(AnalyticsData)
    case fetchComplete
    case fetchError(String)
    case incrementQueryCount
    case resetQueryCount
    case showInHUD
    case hideFromHUD
}
