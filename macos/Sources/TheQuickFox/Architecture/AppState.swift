//
//  AppState.swift
//  TheQuickFox
//
//  Centralized application state following unidirectional data flow principles
//

import Foundation
import Cocoa

// MARK: - App State (Single Source of Truth)

struct AppState {
    var hud: HUDState
    var history: HistoryState
    var session: SessionState
    var subscription: SubscriptionState
    var toast: ToastState
    var metrics: MetricsState

    static let initial = AppState(
        hud: .initial,
        history: .initial,
        session: .initial,
        subscription: .initial,
        toast: .initial,
        metrics: .initial
    )
}

// MARK: - HUD State

struct HUDState {
    var isVisible: Bool
    var mode: HUDMode
    var tone: ResponseTone
    var currentQuery: String
    var response: ResponseState
    var groundingMetadata: GroundingMetadata?  // Web search citations
    var processing: ProcessingState
    var ui: HUDUIState
    var canRespond: Bool  // True if a text-editable element is focused

    static let initial = HUDState(
        isVisible: false,
        mode: .compose,
        tone: .formal,
        currentQuery: "",
        response: .idle,
        groundingMetadata: nil,
        processing: .idle,
        ui: .initial,
        canRespond: true  // Default to true, will be updated when focus is captured
    )
}

struct HUDUIState {
    var panelHeight: CGFloat
    var textIsEditable: Bool
    var loaderIsVisible: Bool
    var responseContainerIsVisible: Bool
    var borderAnimationActive: Bool
    var shouldAnimateToHUD: Bool

    static let initial = HUDUIState(
        panelHeight: 252,  // Base 188 + 64 for icon overflow area
        textIsEditable: true,
        loaderIsVisible: false,
        responseContainerIsVisible: false,
        borderAnimationActive: false,
        shouldAnimateToHUD: false
    )

    static let expanded = HUDUIState(
        panelHeight: 412,  // Base 348 + 64 for icon overflow area
        textIsEditable: true,
        loaderIsVisible: false,
        responseContainerIsVisible: true,
        borderAnimationActive: false,
        shouldAnimateToHUD: false
    )
}

extension HUDUIState: Equatable {
    static func == (lhs: HUDUIState, rhs: HUDUIState) -> Bool {
        return lhs.panelHeight == rhs.panelHeight && lhs.textIsEditable == rhs.textIsEditable
            && lhs.loaderIsVisible == rhs.loaderIsVisible
            && lhs.responseContainerIsVisible == rhs.responseContainerIsVisible
            && lhs.borderAnimationActive == rhs.borderAnimationActive
            && lhs.shouldAnimateToHUD == rhs.shouldAnimateToHUD
    }
}

enum ResponseState {
    case idle
    case streaming(content: String)
    case completed(content: String)
    case failed(error: String)
}

extension ResponseState: Equatable {
    static func == (lhs: ResponseState, rhs: ResponseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.streaming(let lhsContent), .streaming(let rhsContent)):
            return lhsContent == rhsContent
        case (.completed(let lhsContent), .completed(let rhsContent)):
            return lhsContent == rhsContent
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

enum ProcessingState {
    case idle
    case starting
    case active(pipeline: ProcessingInfo)
    case completing
    case failed(error: String)
}

extension ProcessingState: Equatable {
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.starting, .starting), (.completing, .completing):
            return true
        case (.active(let lhsPipeline), .active(let rhsPipeline)):
            return lhsPipeline.query == rhsPipeline.query
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

struct ProcessingInfo {
    let query: String
    let startTime: Date
    let screenshot: WindowScreenshot?

}

// MARK: - History State

struct HistoryState {
    var entries: [HistoryEntry]
    var selectedEntry: HistoryEntry?
    var searchQuery: String
    var filteredEntries: [HistoryEntry]

    static let initial = HistoryState(
        entries: [],
        selectedEntry: nil,
        searchQuery: "",
        filteredEntries: []
    )
}

// MARK: - Session State

/// Reasons why the HUD was closed - used for intent-based session restoration
enum HUDCloseReason: Equatable {
    case escape  // User pressed ESC - intentional close
    case windowButton  // User clicked window X button - intentional close
    case clickOutside  // User clicked outside window - unintentional close
    case focusLost  // App lost focus/system interruption - unintentional close
    case responseUsed  // User successfully used response in Compose mode - intentional close
    case unknown  // Default/fallback case

    /// Whether this close reason indicates intentional closure
    var isIntentional: Bool {
        switch self {
        case .escape, .windowButton, .responseUsed:
            return true
        case .clickOutside, .focusLost, .unknown:
            return false
        }
    }
}

struct SessionState {
    var isActive: Bool
    var canRestore: Bool
    var cachedScreenshot: WindowScreenshot?
    var queryHistory: [String]
    var historyIndex: Int
    var currentDraft: String
    var lastCloseReason: HUDCloseReason

    var responseWasUsed: Bool  // Track if user successfully used the response

    // Migrated from HUDSessionState
    var currentMode: HUDMode
    var currentTone: ResponseTone
    var currentQuery: String
    var currentResponse: String
    var isProcessing: Bool
    var pipeline: PromptPipeline?
    var responseBuffer: String

    // App context
    var isDevelopmentApp: Bool

    // Demo mode context - nil means not in demo mode
    var demoPageContext: String?  // "support", "logo", etc.

    static let initial = SessionState(
        isActive: false,
        canRestore: false,
        cachedScreenshot: nil,
        queryHistory: [],
        historyIndex: -1,
        currentDraft: "",
        lastCloseReason: .unknown,
        responseWasUsed: false,
        currentMode: .compose,
        currentTone: .formal,
        currentQuery: "",
        currentResponse: "",
        isProcessing: false,
        pipeline: nil,
        responseBuffer: "",
        isDevelopmentApp: false,
        demoPageContext: nil
    )
}

// MARK: - Subscription State

struct SubscriptionState {
    var hasActiveSubscription: Bool
    var trialQueriesRemaining: Int
    var subscriptionDetails: SubscriptionDetails?
    var isLoading: Bool
    var lastFetchTime: Date?

    static let initial = SubscriptionState(
        hasActiveSubscription: false,
        trialQueriesRemaining: 0,
        subscriptionDetails: nil,
        isLoading: false,
        lastFetchTime: nil
    )
}

// MARK: - Toast State

struct ToastState {
    var isVisible: Bool
    var message: String
    var errorDetail: String
    var responseText: String
    var appIcon: NSImage?
    var appName: String
    var hudFrame: NSRect?

    static let initial = ToastState(
        isVisible: false,
        message: "",
        errorDetail: "",
        responseText: "",
        appIcon: nil,
        appName: "",
        hudFrame: nil
    )
}

// MARK: - Metrics State

struct MetricsState {
    var data: AnalyticsData?
    var isLoading: Bool
    var lastFetchTime: Date?
    var queriesSinceLastDisplay: Int
    var displayFrequency: Int  // Show celebration every N queries
    var showingInHUD: Bool

    static let initial = MetricsState(
        data: nil,
        isLoading: false,
        lastFetchTime: nil,
        queriesSinceLastDisplay: 0,
        displayFrequency: 10,
        showingInHUD: false
    )
}

// Metrics data models matching the backend API response
struct AnalyticsData: Codable, Equatable {
    let totalQueries: Int
    let queriesByMode: [String: Int]
    let topApps: [AppUsage]
    let currentStreak: Int
    let longestStreak: Int
    let timeSavedMinutes: Int
    let queriesByHour: [Int: Int]
    let dailyUsage: [DailyUsage]
    let timeRange: String

    enum CodingKeys: String, CodingKey {
        case totalQueries = "total_queries"
        case queriesByMode = "queries_by_mode"
        case topApps = "top_apps"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case timeSavedMinutes = "time_saved_minutes"
        case queriesByHour = "queries_by_hour"
        case dailyUsage = "daily_usage"
        case timeRange = "time_range"
    }

    // DEMO: Sample data for visualization
    static let sample = AnalyticsData(
        totalQueries: 147,
        queriesByMode: ["compose": 85, "ask": 42, "code": 20],
        topApps: [
            AppUsage(appName: "Slack", appBundleId: "com.tinyspeck.slackmacgap", count: 45),
            AppUsage(appName: "Arc", appBundleId: "company.thebrowser.Browser", count: 38),
            AppUsage(appName: "Linear", appBundleId: "com.linear", count: 27)
        ],
        currentStreak: 7,
        longestStreak: 14,
        timeSavedMinutes: 735,  // 12 hours 15 minutes
        queriesByHour: [9: 15, 10: 23, 14: 18, 15: 20, 16: 12],
        dailyUsage: [
            DailyUsage(date: "2025-11-18", count: 12),
            DailyUsage(date: "2025-11-19", count: 18),
            DailyUsage(date: "2025-11-20", count: 22),
            DailyUsage(date: "2025-11-21", count: 15),
            DailyUsage(date: "2025-11-22", count: 28),
            DailyUsage(date: "2025-11-23", count: 19),
            DailyUsage(date: "2025-11-24", count: 33)
        ],
        timeRange: "7d"
    )
}

struct AppUsage: Codable, Equatable, Identifiable {
    let appName: String
    let appBundleId: String
    let count: Int

    var id: String { appBundleId }

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case appBundleId = "app_bundle_id"
        case count
    }
}

struct DailyUsage: Codable, Equatable, Identifiable {
    let date: String
    let count: Int

    var id: String { date }
}

// MARK: - Insertion Failure Reasons

public enum InsertionFailureReason {
    case noInputSelected
    case appSwitched
    case lostFocus
    case accessibilityDenied
    case elementUnavailable
    case clipboardFailed
    case appNotResponding
    case unknown

    var userMessage: String {
        switch self {
        case .noInputSelected:
            return "No text field was selected when you opened TheQuickFox"
        case .appSwitched:
            return "The app window is no longer active"
        case .lostFocus:
            return "Focus was lost - click back into the text field"
        case .accessibilityDenied:
            return "Accessibility permission is required"
        case .elementUnavailable:
            return "The text field became unavailable"
        case .clipboardFailed:
            return "Clipboard paste failed"
        case .appNotResponding:
            return "The app didn't respond to paste"
        case .unknown:
            return "Text insertion failed"
        }
    }

    var shortMessage: String {
        switch self {
        case .noInputSelected:
            return "Couldn't find where to paste"
        case .appSwitched:
            return "Original window lost"
        case .lostFocus:
            return "Lost focus"
        case .accessibilityDenied:
            return "Permission denied"
        case .elementUnavailable:
            return "Field unavailable"
        case .clipboardFailed:
            return "Clipboard failed"
        case .appNotResponding:
            return "App not responding"
        case .unknown:
            return "Insertion failed"
        }
    }
}
