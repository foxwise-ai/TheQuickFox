//
//  main.swift
//  TheQuickFox
//
//  Implements a lightweight global detector for a rapid double-press of the
//  Control key (either side) on macOS. When the user presses Control twice
//  within `maxInterval` seconds, the `onTrigger` closure fires.
//
//  Build & run as a console‐style executable. You must grant the binary
//  Accessibility permissions (System Settings ▸ Privacy & Security ▸
//  Accessibility) so it can listen for system-wide events.
//

import AppKit
import Foundation

/// Detects two consecutive Control-key presses within a short time-window.
final class DoubleControlDetector {
    /// Maximum time-interval between the two presses (seconds).
    private let maxInterval: TimeInterval
    /// Handler called on successful detection.
    private let onTrigger: () -> Void

    /// Time the previous Control press occurred (monotonic clock).
    private var lastPressTime: TimeInterval = 0
    /// Indicates whether the Control key was pressed (down) during the current flagsChanged event.
    private var lastControlWasDown = false

    /// Hold a strong reference to the CFMachPort so it isn't deallocated.
    private var eventTap: CFMachPort?

    init(maxInterval: TimeInterval = 0.25, onTrigger: @escaping () -> Void) {
        self.maxInterval = maxInterval
        self.onTrigger = onTrigger
        setupEventTap()
    }

    deinit {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
    }

    /// Set up an event-tap listening for modifier flag changes.
    private func setupEventTap() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            // Re-enable event tap if it gets disabled
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<DoubleControlDetector>.fromOpaque(userInfo)
                    .takeUnretainedValue()
                if let tap = detector.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let detector = Unmanaged<DoubleControlDetector>.fromOpaque(userInfo)
                .takeUnretainedValue()
            detector.handle(event: event)
            return Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
        else {
            print("⚠️ Unable to create event tap. The app needs Accessibility permissions for keyboard shortcuts.")
            print("   Double Control detection will not work until permissions are granted.")
            PermissionsState.shared.hasAccessibilityPermissions = false
            return
        }

        eventTap = tap
        PermissionsState.shared.hasAccessibilityPermissions = true

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("✅ Event tap created successfully. Double Control detection is active.")
    }

    /// Process a `flagsChanged` CGEvent looking for Control key presses.
    private func handle(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 59 || keyCode == 62 else { return }

        let flags = event.flags
        let controlIsDown = flags.contains(.maskControl)
        let now = ProcessInfo.processInfo.systemUptime

        // Timeout: If a key-down was detected but no second press occurred
        // within a reasonable window, assume we missed the key-up and reset.
        // This prevents the detector from getting stuck.
        if lastPressTime != 0 && now - lastPressTime > maxInterval {
            LoggingManager.shared.debug(.generic, "Detector timeout, resetting state.")
            lastPressTime = 0
            lastControlWasDown = false // Force reset
        }

        // Detect the leading edge of a key press (transition from up to down).
        if controlIsDown && !lastControlWasDown {
            LoggingManager.shared.debug(.generic, "Control key down detected.")
            let interval = now - lastPressTime

            // Is this the second press in a double-press?
            if lastPressTime != 0 && interval <= maxInterval {
                LoggingManager.shared.info(.generic, "Double-press detected, triggering action.")
                onTrigger()
                // Reset state immediately to be ready for the next sequence.
                lastPressTime = 0
            } else {
                // This is the first press.
                LoggingManager.shared.debug(.generic, "First press recorded.")
                lastPressTime = now
            }
        }

        // Update the state for the next event, which reflects the current key state.
        lastControlWasDown = controlIsDown
    }
}

// MARK: – Application bootstrap

print("TheQuickFox Double-Control detector running. Press Control twice quickly to trigger…")
let app = NSApplication.shared

// Global dock visibility state - can be toggled via menu
var showInDock = true

// UserDefaults keys
let onboardingCompletedKey = "com.foxwiseai.thequickfox.onboardingCompleted"
let needsPostRestartScreenKey = "com.foxwiseai.thequickfox.needsPostRestartScreen"

// Set app delegate first
NSApp.delegate = AppDelegate.shared

// Create main menu bar
setupMainMenu()

// Create status bar item
setupStatusBarItem()

// Set initial activation policy AFTER everything is set up
if showInDock {
    print("🖥️ Setting activation policy to .regular (dock mode)")
    app.setActivationPolicy(.regular)
    // Activate the app so it shows in dock immediately
    app.activate(ignoringOtherApps: true)
    print("🚀 Activated app - should appear in dock now")
} else {
    print("📱 Setting activation policy to .accessory (background mode)")
    app.setActivationPolicy(.accessory)
}

// MARK: - Status Bar Setup

/// Creates a status bar item for accessing history
func setupStatusBarItem() {
    let statusBar = NSStatusBar.system
    let statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)

    // Set icon
    if let button = statusItem.button {
        var iconImage: NSImage? = nil

        // First try to load the image normally
        iconImage = NSImage(named: "StatusBarIcon")

        // If that fails, try to load PDF explicitly from bundle
        if iconImage == nil,
           let pdfURL = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "pdf"),
           let pdfImage = NSImage(contentsOf: pdfURL) {
            iconImage = pdfImage
            print("📊 Loaded menu bar icon from PDF")
        }

        if let icon = iconImage {
            // Use the image icon
            icon.isTemplate = true  // Important: makes it work properly in light/dark mode
            button.image = icon
            print("✅ Menu bar icon set successfully")
        } else {
            // Fallback to text if icon not found
            print("⚠️  Menu bar icon not found, using text fallback")
            button.title = "RA"  // TheQuickFox
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }
        button.toolTip = "TheQuickFox - Double Control to activate"
    }


    // Create menu using shared builder for consistency with dock and app menus
   let menu = NSMenu()


    // Add all fox tail items (with keyboard shortcuts for status bar)
    for item in createFoxTailMenuItems(includeKeyEquivalents: true) {
        menu.addItem(item)
   }
     menu.addItem(NSMenuItem.separator())

    // Add Quit menu item
    let quitMenuItem = NSMenuItem(
        title: "Quit TheQuickFox",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    menu.addItem(quitMenuItem)

    statusItem.menu = menu

    // Keep reference to status item
    AppDelegate.shared.statusItem = statusItem
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    var statusItem: NSStatusItem?
    var onboardingWindowController: OnboardingWindowController?
    var bugReportWindowController: BugReportWindowController?
    var dmgWarningWindowController: DMGWarningWindowController?

    // App lifecycle methods
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the logging system first
        let _ = LoggingSystem.shared // This triggers initialization

        // Check if running from DMG - if so, show warning and prevent normal startup
        if DMGLaunchDetector.isRunningFromDMG {
            print("⚠️ App is running from a DMG - showing move to Applications prompt")
            LoggingSystem.shared.logWarning(.generic, "App launched from DMG volume", metadata: [
                "bundle_path": AnyCodable(Bundle.main.bundlePath)
            ])

            // Show the DMG warning window
            dmgWarningWindowController = DMGWarningWindowController()
            dmgWarningWindowController?.show()

            // Don't proceed with normal app initialization
            return
        }

        // Initialize toast manager (starts listening for insertion failures)
        let _ = ToastManager.shared

        // Initialize type hint manager (monitors typing patterns to show hints)
        let _ = TypeHintManager.shared

        LoggingSystem.shared.logInfo(.generic, "App launched successfully", metadata: [
            "show_in_dock": AnyCodable(showInDock),
            "app_version": AnyCodable(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        ])

        print("🎯 App did finish launching")
        // Ensure we stay in dock if configured
        if showInDock {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        // Pre-warm HUD so first Control-Control is instant
        DispatchQueue.main.async {
            let _ = HUDManager.shared
            print("✅ HUD pre-warmed")
        }

        // Initialize and configure Sparkle updater after a short delay
        DispatchQueue.main.async {
            UpdateManager.shared.configure()

            // DISABLED: Background check causing immediate error dialog
            // Check for updates in background after launch
            // DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            //     UpdateManager.shared.checkForUpdatesInBackground()
            // }
        }

        // Register device with API and check usage
        Task {
            do {
                let response = try await APIClient.shared.registerDevice()
                print("✅ Device registered - User ID: \(response.data.user_id), Queries remaining: \(response.data.trial_queries_remaining), Has subscription: \(response.data.has_subscription)")

                // Check if we should show any warnings - but only if user doesn't have a subscription
                if !response.data.has_subscription {
                    if response.data.trial_queries_remaining == 0 {
                        await MainActor.run {
                            self.showUpgradePrompt()
                        }
                    } else if response.data.trial_queries_remaining <= 2 {
                        await MainActor.run {
                            self.showTrialWarning(
                                Notification(
                                    name: NSNotification.Name("ShowTrialWarning"),
                                    object: nil,
                                    userInfo: ["remaining": response.data.trial_queries_remaining]
                                )
                            )
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to register device: \(error)")

                // Show error alert to user
                await MainActor.run {
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Unable to Connect to Server"
                    alert.informativeText = "TheQuickFox couldn't connect to the server. Please check your internet connection and try again."
                    alert.addButton(withTitle: "Quit")
                    alert.runModal()

                    // Quit the app
                    NSApplication.shared.terminate(nil)
                }
            }
        }

        // Check if onboarding has been completed
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        let needsPostRestartScreen = UserDefaults.standard.bool(forKey: needsPostRestartScreenKey)

        if !hasCompletedOnboarding {
            // First launch - show onboarding
            print("🎯 First launch detected - showing onboarding")
            DispatchQueue.main.async { [weak self] in
                self?.showOnboarding()
            }
        } else if needsPostRestartScreen {
            // Post-restart after screen recording permission - show completion screen
            let hasAccessibility = PermissionsState.shared.checkAccessibilityPermission()
            let hasScreenRecording = PermissionsState.shared.checkScreenRecordingPermission()

            print("🔍 Post-restart check - accessibility: \(hasAccessibility), screenRecording: \(hasScreenRecording)")

            if hasAccessibility && hasScreenRecording {
                print("🎉 Post-restart detected with all permissions - showing completion screen")
                // Clear the flag
                UserDefaults.standard.set(false, forKey: needsPostRestartScreenKey)

                // Pre-warm HUD synchronously before setting up detector (critical for completion flow)
                print("🔥 Pre-warming HUD for completion screen...")
                let _ = HUDManager.shared
                print("✅ HUD pre-warmed for completion screen")

                // Setup event detector now that HUD is ready
                setupDoubleControlDetector()

                // Show completion screen
                DispatchQueue.main.async { [weak self] in
                    self?.showCompletionScreen()
                }
            } else if hasAccessibility {
                // Screen recording not detected yet - retry after a short delay
                // macOS sometimes needs a moment after restart to report permission correctly
                print("⏳ Screen recording not detected yet, retrying in 1 second...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    let retryScreenRecording = PermissionsState.shared.checkScreenRecordingPermission()
                    print("🔍 Retry check - screenRecording: \(retryScreenRecording)")

                    if retryScreenRecording {
                        print("🎉 Screen recording now granted - showing completion screen")
                        UserDefaults.standard.set(false, forKey: needsPostRestartScreenKey)

                        let _ = HUDManager.shared
                        setupDoubleControlDetector()

                        self?.showCompletionScreen()
                    } else {
                        // Still not granted - show onboarding
                        print("⚠️ Screen recording still not granted - showing onboarding")
                        UserDefaults.standard.set(false, forKey: needsPostRestartScreenKey)
                        self?.showOnboardingWithPermissionsError()
                    }
                }
            } else {
                // Permissions not granted yet - show onboarding with error
                print("⚠️ Post-restart but permissions missing - showing onboarding")
                UserDefaults.standard.set(false, forKey: needsPostRestartScreenKey)
                DispatchQueue.main.async { [weak self] in
                    self?.showOnboardingWithPermissionsError()
                }
            }
        } else if PermissionsState.shared.checkAccessibilityPermission() && PermissionsState.shared.checkScreenRecordingPermission() {
            // Onboarding complete with all permissions - show completion screen on launch
            print("🎉 App launch with completed onboarding - showing completion screen")

            let _ = HUDManager.shared
            setupDoubleControlDetector()

            DispatchQueue.main.async { [weak self] in
                self?.showCompletionScreen()
            }
        } else {
            // Check accessibility permission (this doesn't trigger a dialog)
            let hasAccessibility = PermissionsState.shared.checkAccessibilityPermission()

            if !hasAccessibility {
                // Accessibility permission missing - show onboarding with error
                print("🚀 Accessibility permission missing")
                DispatchQueue.main.async { [weak self] in
                    self?.showOnboardingWithPermissionsError()
                }
            } else {
                // Accessibility is ready - setup event detector
                setupDoubleControlDetector()

                // Start type hint monitoring (requires accessibility permission)
                TypeHintManager.shared.start()

                // Check screen recording permission in background without triggering dialog
                // This will only be checked when user actually tries to use the app
                print("✅ Accessibility permission granted - app ready to use")
            }
        }

        // Listen for permissions error notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboardingWithPermissionsError),
            name: NSNotification.Name("ShowOnboardingPermissionsError"),
            object: nil
        )

        // Listen for TOS onboarding notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboardingWithTOSError),
            name: NSNotification.Name("ShowOnboarding"),
            object: nil
        )

        // Listen for upgrade notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showUpgradePrompt),
            name: NSNotification.Name("ShowUpgradePrompt"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showTrialWarning(_:)),
            name: NSNotification.Name("ShowTrialWarning"),
            object: nil
        )
    }

    // Prevent app from quitting when all windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("🚪 App delegate: preventing quit on last window closed")
        return false // Keep app running in background
    }

    // Provide dock menu when right-clicking the dock icon
    // This gives users access to fox tail menu items even if menu bar icon is hidden under the notch
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return createDockMenu()
    }

    // Handle dock icon click - show completion screen
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingCompletedKey)

        if hasCompletedOnboarding && !flag {
            print("🎉 Dock clicked - showing completion screen")
            showCompletionScreen()
            return false
        }

        return true
    }

    // Handle URL scheme (thequickfox://)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("📱 Received URL: \(url)")

            if url.scheme == "thequickfox" {
                switch url.host {
                case "subscription-success":
                    print("✅ Subscription successful! Reopening app...")
                    // Activate the app and bring it to front
                    NSApplication.shared.activate(ignoringOtherApps: true)

                    // Close any open upgrade window
                    if let upgradeWindow = NSApplication.shared.windows.first(where: { $0.contentViewController is UpgradeWindowController }) {
                        upgradeWindow.close()
                    }

                    // Optionally show a success notification
                    showSubscriptionSuccessNotification()

                default:
                    print("⚠️ Unknown URL path: \(url.host ?? "nil")")
                }
            }
        }
    }

    private func showSubscriptionSuccessNotification() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Subscription Activated!"
            alert.informativeText = "Thank you for subscribing to TheQuickFox. You now have access to the plan features you paid for."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func showHistory() {
        HistoryWindowController.shared.showWindow()
    }

    @objc func showOnboarding() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.show()
    }

    @objc func showCompletionScreen() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.showCompletionMode()
    }

    @objc func showOnboardingWithPermissionsError() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.showWithPermissionsError()
    }

    @objc func showOnboardingWithTOSError() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.showWithTOSError()
    }

    @objc func showAccountSettings() {
        AccountWindowController.show()
    }

    @objc func showMetricsDashboard() {
        MetricsWindowController.show()
    }

    @objc func showNetworkMonitor() {
        NetworkMonitorWindowController.show()
    }

    @objc func checkForUpdates() {
        // Ensure updater is initialized before checking
        if UpdateManager.shared.updater == nil {
            UpdateManager.shared.configure()
        }
        UpdateManager.shared.checkForUpdates()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "TheQuickFox"

        // Get version from Info.plist
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        alert.informativeText = """
            Version \(version) (Build \(build))

            Hey, you're probably here to see the version number. It's in the previous line. You read too far.

            If you're looking to learn more about the makers of TheQuickFox, probably best to head over to our website TheQuickFox.ai

            Thanks so much for using TheQuickFox and the love.

            If you somehow ended up in the wrong street and don't even know what this is..this is an about window to tell you more info about TheQuickFox.
            You're probably wondering why we didn't just say that a long time ago...🤷‍♂️

            Here it is: TheQuickFox will help you write emails to your doctor.

            Press Control twice to activate on any app.

            If that doesn't work go to foxtail menu and click Report Bug...
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor @objc func reportBug() {
        LoggingManager.shared.info(.ui, "User initiated bug report submission")
        bugReportWindowController = BugReportWindowController()
        bugReportWindowController?.showBugReport { [weak self] success in
            if success {
                LoggingManager.shared.info(.ui, "Bug report submitted successfully")
            } else {
                LoggingManager.shared.info(.ui, "Bug report submission cancelled")
            }
            self?.bugReportWindowController = nil
        }
    }

    @MainActor
    @objc func showUpgradePrompt() {
        // Close HUD first to avoid UI confusion
        HUDManager.shared.hideHUD()
        UpgradeWindowController.shared.showUpgradePrompt()
    }

    @objc func showTrialWarning(_ notification: Notification) {
        if let remaining = notification.userInfo?["remaining"] as? Int {
            UpgradeWindowController.shared.showTrialWarning(remaining: remaining)
        }
    }

    @MainActor
    @objc func toggleTypeHints(_ sender: NSMenuItem) {
        let newState = !TypeHintManager.shared.isEnabled
        TypeHintManager.shared.setEnabled(newState)
        sender.state = newState ? .on : .off
        LoggingManager.shared.info(.ui, "Type hints toggled: \(newState ? "enabled" : "disabled")")
    }

    #if DEBUG
    @MainActor
    @objc func testTypeHint() {
        TypeHintManager.shared.showHint(appName: "Test App")
    }
    #endif

}

/// Keep a strong reference.
/// Capture the active window immediately after the shortcut triggers, then
/// present the HUD once the capture finishes. This prevents the HUD itself
/// from being included in the screenshot used for context.
var detector: DoubleControlDetector?

func setupDoubleControlDetector() {
    detector = DoubleControlDetector {
    Task { @MainActor in
        // Check if onboarding window is active - if so, let JavaScript handle it
        if let keyWindow = NSApp.keyWindow, keyWindow.title == "TheQuickFox" {
            print("🎮 Double Control detected but onboarding is active - letting JavaScript handle it")
            return
        }

        let appStore = AppStore.shared
        let hudManager = HUDManager.shared

        // Reset typing hint stats when user activates TQF
        TypeHintManager.shared.resetStats()

        print("🎮 Double Control detected - sessionState: canRestore=\(appStore.sessionState.canRestore)")

        // Log user action with context
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isDevelopmentApp = AppCategoryDetector.isDevelopmentApp(
            bundleID: frontmostApp?.bundleIdentifier,
            appName: frontmostApp?.localizedName
        )
        // Use saved mode preference with fallback logic for Code mode
        let initialMode: HUDMode = UserPreferences.shared.preferredMode(isDevelopmentApp: isDevelopmentApp)

        LoggingSystem.shared.logInfo(.ui, "User triggered HUD via double Control", metadata: [
            "can_restore_session": AnyCodable(appStore.sessionState.canRestore),
            "frontmost_app": AnyCodable(frontmostApp?.localizedName ?? "Unknown"),
            "frontmost_bundle": AnyCodable(frontmostApp?.bundleIdentifier ?? "unknown"),
            "is_development_app": AnyCodable(isDevelopmentApp),
            "initial_mode": AnyCodable(initialMode.rawValue)
        ])

        print("🎮 Double Control detected - sessionState: canRestore=\(appStore.sessionState.canRestore)")
        print("🔍 Detected app: \(frontmostApp?.localizedName ?? "Unknown") - isDev: \(isDevelopmentApp), mode: \(initialMode)")

        // Check if HUD is already visible
        if appStore.hudState.isVisible {

            print("🔄 HUD already visible - re-activating with new window context")
           // HUD is already visible, handle re-activation

            // Save current query and mode
           let currentQuery = appStore.hudState.currentQuery
            let currentMode = appStore.hudState.mode
            let currentWindowFrame = hudManager.getCurrentWindowFrame()

            // Find and highlight the frontmost window first
            if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                // Get the frontmost app's PID
                if let targetPID = frontmostApp?.processIdentifier {
                    // Find the best window from the frontmost app using shared logic
                    if let window = WindowSelector.findBestWindow(targetPID: targetPID, windowList: infoList) {
                        // Show highlight on active window
                        let windowTitle = window[kCGWindowName as String] as? String ?? "(no title)"
                        let windowID = window[kCGWindowNumber as String] as? Int ?? 0
                        let ownerName = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
                        let bounds = window[kCGWindowBounds as String] as? [String: Any]
                        let layer = window[kCGWindowLayer as String] as? Int ?? 0

                        let logMessage = "🌈 Highlighted window (re-activation) - App: \(ownerName), Title: '\(windowTitle)', ID: \(windowID), Layer: \(layer), Bounds: \(String(describing: bounds))"
                        LoggingManager.shared.info(.ui, logMessage)
                        ProductionLogger.shared.log(.info, .ui, logMessage)
                        WindowHighlighter.shared.highlight(windowInfo: window, duration: 3.0)
                    }
                }
            }


            // Hide briefly
           appStore.dispatch(.hud(.hideForReactivation))


            // Capture new screenshot of the current frontmost window (no rainbow highlight)
            print("📸 Capturing new screenshot for re-activation...")
           ScreenshotManager.shared.requestCapture { result in

                Task { @MainActor in
                   let newScreenshot: WindowScreenshot?
                    switch result {

                    case .success(let screenshot):
                       print("✅ New screenshot captured for re-activation")

                        newScreenshot = screenshot
                    case .failure(let error):
                        print("⚠️ Screenshot failed, keeping cached: \(error)")
                        newScreenshot = appStore.sessionState.cachedScreenshot
                    }


                    // Start new session with the new screenshot
                   appStore.dispatch(.session(.start(
                        mode: currentMode,
                        tone: appStore.hudState.tone,
                        screenshot: newScreenshot

                    )))

                // Prepare window with animation
                appStore.dispatch(.hud(.prepareWindow))
                    // Prepare window
                    appStore.dispatch(.hud(.prepareWindow))


                    // Restore the query
                    if !currentQuery.isEmpty {
                        appStore.dispatch(.hud(.updateQuery(currentQuery)))
                   }
                }
            }
            return
        }

        // Intent-based session and screenshot logic
        if appStore.sessionState.canRestore {
            print("🔄 Restoring existing session - no screenshot needed")
            // True session restoration - use cached data, no screenshot waste
            hudManager.presentHUD(initialMode: initialMode)
        } else {

            print("🆕 Starting fresh session - preparing HUD")
            // Skip window highlighting on Intel Macs (animation is disabled for performance)
            if !ArchitectureDetector.isIntelMac {

                // Find and highlight the frontmost window immediately (Apple Silicon only)
                if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                    // Get the frontmost app's PID (already detected above)
                    if let targetPID = frontmostApp?.processIdentifier {
                        // Find the best window from the frontmost app using shared logic
                        if let window = WindowSelector.findBestWindow(targetPID: targetPID, windowList: infoList) {
                            // Show highlight immediately
                            let windowTitle = window[kCGWindowName as String] as? String ?? "(no title)"
                            let windowID = window[kCGWindowNumber as String] as? Int ?? 0
                            let ownerName = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
                            let bounds = window[kCGWindowBounds as String] as? [String: Any]
                            let layer = window[kCGWindowLayer as String] as? Int ?? 0

                            let logMessage = "🌈 Highlighted window - App: \(ownerName), Title: '\(windowTitle)', ID: \(windowID), Layer: \(layer), Bounds: \(String(describing: bounds))"
                            LoggingManager.shared.info(.ui, logMessage)
                            ProductionLogger.shared.log(.info, .ui, logMessage)
                            WindowHighlighter.shared.highlight(windowInfo: window, duration: 3.0)
                        } else {
                            print("⚠️ No suitable window found for highlighting")
                       }
                    }
                }
            }


            // Start the HUD preparation
           hudManager.presentHUD(initialMode: initialMode)

            // Capture screenshot in background
            print("📸 Capturing screenshot in background...")
            ScreenshotManager.shared.requestCapture { result in
                Task { @MainActor in
                    switch result {
                    case .success(let screenshot):
                        print("✅ Screenshot captured, updating session")
                        // Update the session with the screenshot
                        appStore.dispatch(.session(.updateScreenshot(screenshot)))
                    case .failure(let error):
                        print("❌ Screenshot capture failed: \(error)")
                        // Session continues without screenshot
                    }
                }
            }
        }
    }
    }
}

// Start the Cocoa event loop.
app.run()
