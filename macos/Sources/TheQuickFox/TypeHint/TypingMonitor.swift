//
//  TypingMonitor.swift
//  TheQuickFox
//
//  Monitors user typing patterns to detect when they might benefit from AI assistance.
//  Uses an event tap to track keystrokes system-wide and identifies "struggle" patterns.
//
//  Performance optimized:
//  - Stats tracked synchronously with lock (no Task per keystroke)
//  - MainActor dispatch only when hint threshold is reached
//  - Threshold checks are O(1) arithmetic
//

import AppKit
import Foundation

/// Thread-safe typing statistics for struggle detection
/// Uses os_unfair_lock for minimal overhead (~25ns vs ~100ns for NSLock)
final class TypingStats {
    private var unfairLock = os_unfair_lock()

    private var _totalKeystrokes: Int = 0
    private var _backspaceCount: Int = 0
    private var _pauseCount: Int = 0
    private var _lastKeystrokeTime: TimeInterval = 0  // Use TimeInterval instead of Date for speed

    var totalKeystrokes: Int {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        return _totalKeystrokes
    }

    /// Reset stats for a new typing session
    func reset() {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        _totalKeystrokes = 0
        _backspaceCount = 0
        _pauseCount = 0
        _lastKeystrokeTime = 0
    }

    /// Record a keystroke and return (totalCount, shouldCheckHint)
    /// shouldCheckHint is true every 10 keystrokes to batch threshold checks
    func recordKeystroke(isBackspace: Bool, pauseThreshold: TimeInterval) -> (total: Int, shouldCheck: Bool) {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        // Use CACurrentMediaTime() - faster than Date()
        let now = CACurrentMediaTime()

        // Detect pause (gap between keystrokes)
        if _lastKeystrokeTime > 0 && (now - _lastKeystrokeTime) > pauseThreshold {
            _pauseCount += 1
        }

        _totalKeystrokes += 1
        if isBackspace {
            _backspaceCount += 1
        }
        _lastKeystrokeTime = now

        // Only check every 10 keystrokes to reduce overhead
        let shouldCheck = _totalKeystrokes % 10 == 0
        return (_totalKeystrokes, shouldCheck)
    }

    /// Calculate struggle score (0.0 - 1.0)
    /// Higher scores indicate more struggling
    func struggleScore() -> Double {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        guard _totalKeystrokes > 0 else { return 0 }

        // Backspace ratio: high backspace = struggle
        let backspaceRatio = Double(_backspaceCount) / Double(_totalKeystrokes)

        // Pause frequency: many pauses = thinking/struggling
        let pauseRatio = Double(_pauseCount) / Double(max(1, _totalKeystrokes / 10))

        // Weighted combination
        let score = (backspaceRatio * 0.6) + (min(pauseRatio, 1.0) * 0.4)
        return min(score, 1.0)
    }
}

/// Configuration for typing monitor thresholds
struct TypingMonitorConfig {
    /// Minimum keystrokes before showing hint (prevents premature hints)
    var minKeystrokesForHint: Int = 80

    /// High threshold - show hint after this many keystrokes regardless of struggle
    var maxKeystrokesBeforeHint: Int = 200

    /// Struggle threshold (0.0-1.0) - if struggle score exceeds this, show hint earlier
    var struggleThreshold: Double = 0.25

    /// Minimum keystrokes before considering struggle-based hint
    var minKeystrokesForStruggleHint: Int = 60

    /// Pause detection threshold in seconds
    var pauseThresholdSeconds: TimeInterval = 3.0

    /// Cooldown period after showing a hint (seconds)
    var hintCooldownSeconds: TimeInterval = 120.0

    /// Apps to exclude from monitoring (by bundle ID)
    var excludedBundleIDs: Set<String> = [
        "com.foxwiseai.thequickfox",  // TheQuickFox itself
        "com.apple.Terminal",          // Terminal apps handle differently
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable"
    ]
}

/// Monitors typing patterns to detect when user might benefit from TheQuickFox
@MainActor
final class TypingMonitor {

    // MARK: - Singleton

    static let shared = TypingMonitor()

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var isMonitoring = false
    private let stats = TypingStats()  // Thread-safe, accessed from callback
    private var config = TypingMonitorConfig()
    private var lastHintTime: Date?

    // Accessed from multiple threads - use atomic operations
    private let currentAppBundleIDLock = NSLock()
    private var _currentAppBundleID: String?
    private var currentAppBundleID: String? {
        get {
            currentAppBundleIDLock.lock()
            defer { currentAppBundleIDLock.unlock() }
            return _currentAppBundleID
        }
        set {
            currentAppBundleIDLock.lock()
            defer { currentAppBundleIDLock.unlock() }
            _currentAppBundleID = newValue
        }
    }

    // Track if HUD is visible (cached, updated via notification)
    private var hudIsVisible = false

    // Cached config values for thread-safe access from callback
    // These are copied from config when monitoring starts
    private var cachedPauseThreshold: TimeInterval = 3.0
    private var cachedExcludedBundleIDs: Set<String> = []
    private var cachedMinForStruggle: Int = 30
    private var cachedMaxKeystrokes: Int = 150

    /// Callback when a hint should be shown
    var onShouldShowHint: ((String) -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Start monitoring typing patterns
    func startMonitoring() {
        guard !isMonitoring else { return }

        // Cache config values for thread-safe access from callback
        cachedPauseThreshold = config.pauseThresholdSeconds
        cachedExcludedBundleIDs = config.excludedBundleIDs
        cachedMinForStruggle = config.minKeystrokesForStruggleHint
        cachedMaxKeystrokes = config.maxKeystrokesBeforeHint

        setupEventTap()
        setupAppSwitchObserver()
        setupHUDVisibilityObserver()

        isMonitoring = true
        LoggingManager.shared.info(.generic, "TypingMonitor started")
    }

    /// Stop monitoring
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        NotificationCenter.default.removeObserver(self)
        isMonitoring = false
        stats.reset()

        LoggingManager.shared.info(.generic, "TypingMonitor stopped")
    }

    /// Reset typing statistics (called when hint is shown or user activates TQF)
    func resetStats() {
        stats.reset()
        LoggingManager.shared.debug(.generic, "TypingMonitor stats reset")
    }

    /// Update configuration
    func updateConfig(_ newConfig: TypingMonitorConfig) {
        config = newConfig
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        // Monitor key down events
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            // Re-enable if disabled
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            // Quick checks that don't need MainActor (all thread-safe)
            if let bundleID = monitor.currentAppBundleID {
                // Skip if explicitly excluded
                if monitor.cachedExcludedBundleIDs.contains(bundleID) {
                    return Unmanaged.passUnretained(event)
                }
                // Skip development/code apps - users are writing code, not struggling
                if AppCategoryDetector.isDevelopmentApp(bundleID: bundleID, appName: nil) {
                    return Unmanaged.passUnretained(event)
                }
            }

            // Skip if HUD is visible (cached value, updated via Combine)
            if monitor.hudIsVisible {
                return Unmanaged.passUnretained(event)
            }

            // Extract key info synchronously
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Tab key (48) - reset stats (user navigating to new field)
            if keyCode == 48 {
                monitor.stats.reset()
                return Unmanaged.passUnretained(event)
            }

            // Skip non-typing keys (navigation, submission)
            // Arrow keys: 123 (left), 124 (right), 125 (down), 126 (up)
            // Enter/Return: 36, 76 - skip but DON'T reset (nudge toward longer messages)
            let isNonTypingKey = (keyCode >= 123 && keyCode <= 126) ||  // arrows
                                 keyCode == 36 || keyCode == 76          // enter/return
            if isNonTypingKey {
                return Unmanaged.passUnretained(event)
            }

            let isBackspace = keyCode == 51

            // Update stats synchronously (thread-safe)
            let (total, shouldCheck) = monitor.stats.recordKeystroke(
                isBackspace: isBackspace,
                pauseThreshold: monitor.cachedPauseThreshold
            )

            // Only dispatch to MainActor when we might need to show a hint
            // This happens every 10 keystrokes OR when approaching threshold
            if shouldCheck || total >= monitor.cachedMinForStruggle {
                // Check if we're close to a threshold
                if total >= monitor.cachedMinForStruggle || total >= monitor.cachedMaxKeystrokes {
                    Task { @MainActor in
                        monitor.checkForHintTrigger()
                    }
                }
            }

            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,  // Listen-only, don't consume events
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            LoggingManager.shared.error(.generic, "TypingMonitor: Unable to create event tap")
            return
        }

        eventTap = tap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        LoggingManager.shared.debug(.generic, "TypingMonitor event tap created")
    }

    // MARK: - App Switch Observer

    private func setupAppSwitchObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeAppDidChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let newBundleID = app.bundleIdentifier

        // Reset stats when switching apps
        if newBundleID != currentAppBundleID {
            currentAppBundleID = newBundleID
            stats.reset()
            LoggingManager.shared.debug(.generic, "TypingMonitor: App switched to \(newBundleID ?? "unknown"), stats reset")
        }
    }

    // MARK: - HUD Visibility Observer

    private func setupHUDVisibilityObserver() {
        // Cache HUD visibility to avoid MainActor access in callback
        Task { @MainActor in
            // Initial value
            self.hudIsVisible = AppStore.shared.hudState.isVisible

            // Observe changes
            AppStore.shared.hudStatePublisher
                .map(\.isVisible)
                .removeDuplicates()
                .sink { [weak self] isVisible in
                    self?.hudIsVisible = isVisible
                }
                .store(in: &hudVisibilityCancellable)
        }
    }

    private var hudVisibilityCancellable = Set<AnyCancellable>()

    // MARK: - Hint Logic

    private func checkForHintTrigger() {
        // Check cooldown
        if let lastHint = lastHintTime,
           Date().timeIntervalSince(lastHint) < config.hintCooldownSeconds {
            return
        }

        let total = stats.totalKeystrokes
        var shouldShowHint = false
        var reason = ""

        // High keystroke count - always show hint
        if total >= config.maxKeystrokesBeforeHint {
            shouldShowHint = true
            reason = "extended_typing"
        }
        // Struggle-based hint (must have minimum keystrokes)
        else if total >= config.minKeystrokesForStruggleHint {
            let score = stats.struggleScore()
            if score >= config.struggleThreshold {
                shouldShowHint = true
                reason = "struggle_detected"
            }
        }
        // Minimum keystrokes reached with moderate struggle
        else if total >= config.minKeystrokesForHint {
            let score = stats.struggleScore()
            if score >= config.struggleThreshold * 0.8 {
                shouldShowHint = true
                reason = "moderate_struggle"
            }
        }

        if shouldShowHint {
            triggerHint(reason: reason)
        }
    }

    private func triggerHint(reason: String) {
        lastHintTime = Date()

        let keystrokes = stats.totalKeystrokes
        let struggle = stats.struggleScore()

        LoggingManager.shared.info(.generic, "TypingMonitor triggering hint - reason: \(reason), keystrokes: \(keystrokes), struggle: \(String(format: "%.2f", struggle))")

        // Get current app info for context
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "this app"

        onShouldShowHint?(appName)

        // Reset stats after showing hint
        stats.reset()
    }
}

import Combine
