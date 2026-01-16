//
//  OnboardingWindowController.swift
//  TheQuickFox
//
//  Window controller for the onboarding flow using WKWebView
//

import Cocoa
import WebKit

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    private var webView: WKWebView!
    private var messageHandler: OnboardingMessageHandler!
    private var loadingView: NSView!
    private var headerContentView: NSView!
    private var iconImageView: NSImageView!
    private var titleImageView: NSImageView!
    private var containerView: NSView!
    private var animationCompleted = false
    private let headerHeight: CGFloat = 70
    private var shouldShowPermissionsError = false
    private var shouldShowTOSError = false
    private var isCompletionMode = false
    var permissionStatusTimer: Timer?


    // MARK: - Initialization

    convenience init() {
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "TheQuickFox"
        window.minSize = NSSize(width: 720, height: 640)
        window.center()

        // Initialize with window
        self.init(window: window)

        // Set window delegate to receive close notifications
        window.delegate = self

        // Initialize message handler with reference to self
        messageHandler = OnboardingMessageHandler()
        messageHandler.windowController = self

        setupContainerView()
        setupLoadingView()
        setupWebView()
        loadOnboardingContent()
    }

    deinit {
        // Clean up timer when window controller is deallocated
        permissionStatusTimer?.invalidate()
        permissionStatusTimer = nil
        print("🧹 OnboardingWindowController deinit - timer cleaned up")
    }

    func windowWillClose(_ notification: Notification) {
        // Clean up timer when window is about to close
        permissionStatusTimer?.invalidate()
        permissionStatusTimer = nil

        // Remove HUD notification observer
        NotificationCenter.default.removeObserver(self, name: .hudDidAppear, object: nil)

        print("🧹 Window closing - timer and observers cleaned up")
    }

    // MARK: - Setup

    private func setupContainerView() {
        // Create main container that will hold both loading view and web view
        guard let window = window else {
            print("❌ No window available")
            return
        }
        let contentRect = NSRect(x: 0, y: 0, width: 720, height: 520)
        containerView = NSView(frame: contentRect)
        containerView.wantsLayer = true
        // containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        if #available(macOS 10.14, *) {
            let isDarkMode =
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            // Match CSS --bg-secondary: #1c1c1e (dark) or #f5f5f7 (light)
            if isDarkMode {
                containerView.layer?.backgroundColor =
                    NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor
            } else {
                containerView.layer?.backgroundColor =
                    NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0).cgColor
            }
        } else {
            containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        containerView.autoresizingMask = [.width, .height]
        window.contentView = containerView
        print("✅ Container view setup with frame: \(containerView.frame)")
    }

    private func setupLoadingView() {
        // Create loading view container
        loadingView = NSView(frame: .zero)
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.wantsLayer = true
        // Match background with web content bg-secondary
        if #available(macOS 10.14, *) {
            let isDarkMode =
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            // Match CSS --bg-secondary: #1c1c1e (dark) or #f5f5f7 (light)
            if isDarkMode {
                loadingView.layer?.backgroundColor =
                    NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor
            } else {
                loadingView.layer?.backgroundColor =
                    NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0).cgColor
            }
        } else {
            loadingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        // Create icon image view
        iconImageView = NSImageView(frame: .zero)
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.wantsLayer = true

        // Load app icon
        if let appIcon = NSImage(named: "AppIcon") {
            iconImageView.image = appIcon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        {
            iconImageView.image = icon
        } else {
            // Fallback to system icon
            iconImageView.image = NSImage(named: NSImage.applicationIconName)
        }

        // Create title image view
        titleImageView = NSImageView(frame: .zero)
        titleImageView.imageScaling = .scaleProportionallyUpOrDown
        titleImageView.wantsLayer = true

        // Load TheQuickFox logo
        if let logoImage = NSImage(named: "TheQuickFoxLogo") {
            titleImageView.image = logoImage
        } else if let logoURL = Bundle.main.url(
            forResource: "TheQuickFoxLogo", withExtension: "png"),
            let logo = NSImage(contentsOf: logoURL)
        {
            titleImageView.image = logo
        }

        // Create header content container (icon + title)
        headerContentView = NSView(frame: .zero)
        headerContentView.wantsLayer = true
        loadingView.addSubview(headerContentView)

        // Add subviews to header content
        headerContentView.addSubview(iconImageView)
        headerContentView.addSubview(titleImageView)

        // Don't use constraints for loading view - use manual layout instead
        // We'll set frames after adding to container

        // Add loading view to container
        containerView.addSubview(loadingView)
        loadingView.frame = containerView.bounds
        loadingView.autoresizingMask = []  // No autoresizing during animation

        // Layout header content centered in the loading view
        let containerBounds = containerView.bounds
        let iconSize: CGFloat = 128
        let spacing: CGFloat = 24
        // Calculate title image size based on aspect ratio
        let titleHeight: CGFloat = 48
        let titleWidth: CGFloat = 160  // Approximate width for TheQuickFox logo
        let contentHeight = max(iconSize, titleHeight)
        let contentWidth = iconSize + spacing + titleWidth
        let startX = (containerBounds.width - contentWidth) / 2
        let startY = (containerBounds.height - contentHeight) / 2

        headerContentView.frame = NSRect(
            x: startX, y: startY, width: contentWidth, height: contentHeight)
        iconImageView.frame = NSRect(
            x: 0, y: (contentHeight - iconSize) / 2, width: iconSize, height: iconSize)
        titleImageView.frame = NSRect(
            x: iconSize + spacing, y: (contentHeight - titleHeight) / 2,
            width: titleWidth, height: titleHeight)

        print("📐 Header content frame: \(headerContentView.frame)")
        print("📐 Icon frame: \(iconImageView.frame)")
        print("📐 Title frame: \(titleImageView.frame)")
        print("📐 Container bounds: \(containerBounds)")
    }

    private func setupWebView() {
        // Configure WKWebView with message handler
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Add message handler for JS->Native communication
        userContentController.add(messageHandler, name: "onboarding")
        configuration.userContentController = userContentController

        // Create web view with initial frame
        let initialFrame =
            window?.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 720, height: 520)
        webView = WKWebView(frame: initialFrame, configuration: configuration)
        // Don't set translatesAutoresizingMaskIntoConstraints to false since we're using frames

        // Configure appearance
        webView.wantsLayer = true
        if #available(macOS 10.14, *) {
            // Make background transparent
            webView.setValue(false, forKey: "drawsBackground")
            webView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Add web view to container behind the loading view but keep it hidden
        containerView.addSubview(webView, positioned: .below, relativeTo: loadingView)
        // Web content starts below where the header will be
        let headerHeight = self.headerHeight
        var webViewFrame = containerView.bounds
        webViewFrame.origin.y = 0  // Origin is at bottom in macOS
        webViewFrame.size.height = containerView.bounds.height - headerHeight
        webView.frame = webViewFrame
        webView.autoresizingMask = [.width, .height]
        webView.alphaValue = 0
        webView.wantsLayer = true

        // Set navigation delegate
        webView.navigationDelegate = self
    }

    private func loadOnboardingContent() {
        let fileManager = FileManager.default
        var htmlURL: URL?
        var baseURL: URL?

        print("🔄 Starting to load onboarding content...")

        // Try multiple paths in order of preference
        let possiblePaths = [
            // 1. App bundle Resources folder (for built app)
            Bundle.main.resourceURL?.appendingPathComponent("Onboarding/index.html"),
            // 2. Swift Package Manager resources (for swift run)
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("TheQuickFox_TheQuickFox.resources/Onboarding/index.html"),
            // 3. Development path (source directory)
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Sources/TheQuickFox/Onboarding/Resources/index.html"),
        ]

        for path in possiblePaths.compactMap({ $0 }) {
            print("🔍 Checking path: \(path.path)")
            if fileManager.fileExists(atPath: path.path) {
                htmlURL = path
                baseURL = path.deletingLastPathComponent()
                print("✅ Found onboarding HTML at: \(path.path)")
                break
            }
        }

        guard let finalURL = htmlURL, let finalBaseURL = baseURL else {
            print("❌ Could not find onboarding HTML file in any expected location")
            return
        }

        print("📄 Loading HTML from: \(finalURL.path)")
        print("📁 Base URL: \(finalBaseURL.path)")

        // Load the HTML file with its base directory for relative resources
        let request = webView.loadFileURL(finalURL, allowingReadAccessTo: finalBaseURL)
        print("🔗 Load request: \(request)")

    }

    // MARK: - Public Methods

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Show the completion screen after app restart (post screen recording permission)
    func showCompletionMode() {
        isCompletionMode = true

        // Load completion.html instead of index.html
        loadCompletionContent()

        // Listen for HUD appearing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHUDAppeared),
            name: .hudDidAppear,
            object: nil
        )

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleHUDAppeared() {
        print("🎉 HUD appeared - notifying completion screen")
        // Call JS to transition to success state
        webView?.evaluateJavaScript("window.onHUDAppeared();") { _, error in
            if let error = error {
                print("❌ Failed to notify JS of HUD appearance: \(error)")
            }
        }
    }

    private func loadCompletionContent() {
        let fileManager = FileManager.default
        var htmlURL: URL?
        var baseURL: URL?

        print("🔄 Loading completion content...")

        let possiblePaths = [
            Bundle.main.resourceURL?.appendingPathComponent("Onboarding/completion.html"),
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("TheQuickFox_TheQuickFox.resources/Onboarding/completion.html"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Sources/TheQuickFox/Onboarding/Resources/completion.html"),
        ]

        for path in possiblePaths.compactMap({ $0 }) {
            print("🔍 Checking path: \(path.path)")
            if fileManager.fileExists(atPath: path.path) {
                htmlURL = path
                baseURL = path.deletingLastPathComponent()
                print("✅ Found completion HTML at: \(path.path)")
                break
            }
        }

        guard let finalURL = htmlURL, let finalBaseURL = baseURL else {
            print("❌ Could not find completion HTML file")
            return
        }

        webView.loadFileURL(finalURL, allowingReadAccessTo: finalBaseURL)
    }

    /// Show completion content immediately without header animation
    private func showCompletionContent() {
        print("🎉 Showing completion content")

        // Hide the loading view
        loadingView.isHidden = true

        // Expand web view to fill the container (no header needed)
        webView.frame = containerView.bounds
        webView.alphaValue = 1
    }

    // MARK: - Permission Status Updates

    /// Track if we've already checked screen recording to avoid repeated dialogs
    private var hasCheckedScreenRecording = false

    /// Update permission status in JS - panel-aware to avoid triggering unwanted dialogs
    /// Panel 3 = Accessibility, Panel 4 = Email/TOS (no permissions), Panel 5 = Screen Recording
    private func updatePermissionStatus(forPanel panel: Int) {
        // Only check the permission relevant to the current panel
        let accessibilityGranted = PermissionsState.shared.checkAccessibilityPermission()

        // For screen recording, only use cached value to avoid triggering the dialog repeatedly
        // The actual check happens only when user clicks "Enable" button
        let screenRecordingGranted = PermissionsState.shared.hasScreenRecordingPermissions

        print("🔍 Updating permission status (panel \(panel)) - accessibility: \(accessibilityGranted), screenRecording: \(screenRecordingGranted)")
        let script = """
            window.updatePermissionStatus({
                accessibility: \(accessibilityGranted ? "true" : "false"),
                screenRecording: \(screenRecordingGranted ? "true" : "false")
            });
        """
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ Failed to update permission status: \(error)")
            } else {
                print("✅ Permission status updated in JS")
            }
        }
    }

    /// Check screen recording permission once - called after user clicks Enable and returns from System Settings
    func checkScreenRecordingOnce() {
        let granted = PermissionsState.shared.checkScreenRecordingPermission()
        print("🔍 Screen recording check: \(granted)")
        let script = """
            window.updatePermissionStatus({
                accessibility: \(PermissionsState.shared.hasAccessibilityPermissions ? "true" : "false"),
                screenRecording: \(granted ? "true" : "false")
            });
        """
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Observer for app activation
    private var screenRecordingObserver: NSObjectProtocol?

    /// Start monitoring for app activation to check screen recording permission
    func startScreenRecordingMonitor() {
        // Remove any existing observer
        if let observer = screenRecordingObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Listen for app becoming active
        screenRecordingObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            print("🔍 App became active - checking screen recording permission")
            self.checkScreenRecordingOnce()

            // Remove observer after one check
            if let observer = self.screenRecordingObserver {
                NotificationCenter.default.removeObserver(observer)
                self.screenRecordingObserver = nil
            }
        }
    }

    /// Evaluate JavaScript in the webView - used by message handler for callbacks
    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        webView?.evaluateJavaScript(script, completionHandler: completion)
    }

    func startPermissionStatusTimer() {
        // Stop any existing timer
        permissionStatusTimer?.invalidate()

        // Get current panel and do initial check
        webView?.evaluateJavaScript("window.currentPanel") { [weak self] result, _ in
            guard let self = self else { return }
            let panel = result as? Int ?? 3
            self.updatePermissionStatus(forPanel: panel)
        }

        // Update permission status every second while on a permissions page (panel 3 or 5)
        permissionStatusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            // Check which panel we're on
            self.webView?.evaluateJavaScript("window.currentPanel") { result, error in
                if let panel = result as? Int, panel == 3 || panel == 5 {
                    // Only update for permission panels (3 = Accessibility, 5 = Screen Recording)
                    self.updatePermissionStatus(forPanel: panel)
                } else {
                    // Stop timer when leaving permission panels
                    timer.invalidate()
                    self.permissionStatusTimer = nil
                }
            }
        }
    }

    func showWithPermissionsError() {
        shouldShowPermissionsError = true
        show()
    }

    func showWithTOSError() {
        shouldShowTOSError = true
        show()
    }

    func insertTextIntoReplyField(_ text: String, completion: @escaping (Bool) -> Void) {
        // Use JSON encoding to safely pass the text to JavaScript
        guard let textData = try? JSONEncoder().encode(text),
              let jsonText = String(data: textData, encoding: .utf8) else {
            completion(false)
            return
        }

        // JavaScript to insert text into the reply field
        let script = """
            (function() {
                const replyField = document.getElementById('reply-field');
                if (replyField) {
                    const textToInsert = \(jsonText);

                    // Insert text at cursor position or replace selection
                    const start = replyField.selectionStart;
                    const end = replyField.selectionEnd;
                    const currentText = replyField.value;

                    replyField.value = currentText.substring(0, start) + textToInsert + currentText.substring(end);

                    // Move cursor to end of inserted text
                    const newCursorPos = start + textToInsert.length;
                    replyField.setSelectionRange(newCursorPos, newCursorPos);

                    // Focus the field
                    replyField.focus();

                    // Trigger input event
                    replyField.dispatchEvent(new Event('input', { bubbles: true }));

                    return true;
                }
                return false;
            })();
        """

        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("❌ Failed to insert text in demo mode: \(error)")
                completion(false)
            } else if let success = result as? Bool {
                completion(success)
            } else {
                completion(false)
            }
        }
    }


    // MARK: - Private Methods


    private func animateToWebView() {
        // Prevent double animation
        guard !animationCompleted else {
            print("⚠️ Animation already completed")
            return
        }
        animationCompleted = true

        print("🎨 Starting animation...")

        // Don't re-add loading view, just animate it

        // Create smaller versions of icon and title for header
        let headerHeight = self.headerHeight
        let finalIconSize: CGFloat = 32
        let finalTitleHeight: CGFloat = 24
        let finalTitleWidth: CGFloat = 80
        let spacing: CGFloat = 12

        // Target frame for the header after animation (top-aligned, fixed height)
        let headerFrame = NSRect(
            x: 0,
            y: containerView.bounds.height - headerHeight,
            width: containerView.bounds.width,
            height: headerHeight
        )

        // Final header content frame centered within header
        let finalContentHeight = max(finalIconSize, finalTitleHeight)
        let finalContentWidth = finalIconSize + spacing + finalTitleWidth
        let finalContentX = (headerFrame.width - finalContentWidth) / 2
        let finalContentY = (headerFrame.height - finalContentHeight) / 2

        print(
            "📍 Final header content frame: x=\(finalContentX), y=\(finalContentY), w=\(finalContentWidth), h=\(finalContentHeight)"
        )

        // Animate the transition
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            // Shrink loading view into header at the top
            loadingView.animator().frame = headerFrame

            // Animate header content to centered position inside header
            headerContentView.animator().frame = NSRect(
                x: finalContentX,
                y: finalContentY,
                width: finalContentWidth,
                height: finalContentHeight
            )

            // Resize icon and title within the header content container
            iconImageView.animator().frame = NSRect(
                x: 0,
                y: (finalContentHeight - finalIconSize) / 2,
                width: finalIconSize,
                height: finalIconSize
            )

            titleImageView.animator().frame = NSRect(
                x: finalIconSize + spacing,
                y: (finalContentHeight - finalTitleHeight) / 2,
                width: finalTitleWidth,
                height: finalTitleHeight
            )

            // Fade in web view
            webView.animator().alphaValue = 1

        }) {
            // Animation completed
            print("✨ Animation completed!")

            // Debug the final state
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("🔍 POST-ANIMATION STATE:")
                print("  Loading view frame: \(self.loadingView.frame)")
                print("  Loading view bounds: \(self.loadingView.bounds)")
                print("  Header content frame: \(self.headerContentView.frame)")
                print("  Icon frame: \(self.iconImageView.frame)")
                print("  Title frame: \(self.titleImageView.frame)")
                print("  Loading view superview: \(String(describing: self.loadingView.superview))")
                print("  Loading view layer: \(String(describing: self.loadingView.layer))")
                print(
                    "  View hierarchy: \(self.containerView.subviews.map { String(describing: type(of: $0)) })"
                )

                // Check if we need to show permissions error
                if self.shouldShowPermissionsError {
                    self.shouldShowPermissionsError = false
                    let script = """
                        window.navigateToPermissionsWithError('Accessibility permission is required for TheQuickFox to work.');
                    """
                    self.webView?.evaluateJavaScript(script) { _, error in
                        if let error = error {
                            print("❌ Failed to navigate to permissions with error: \(error)")
                        }
                    }
                }

                // Check if we need to show TOS error
                if self.shouldShowTOSError {
                    self.shouldShowTOSError = false
                    let script = """
                        window.navigateToPermissionsWithError('Please accept our Terms of Service to continue using TheQuickFox.');
                    """
                    self.webView?.evaluateJavaScript(script) { _, error in
                        if let error = error {
                            print("❌ Failed to navigate to TOS error: \(error)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension OnboardingWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("🌐 WebView started loading...")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ WebView finished loading!")

        // Inject system appearance
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let script = "window.setSystemAppearance('\(isDarkMode ? "dark" : "light")')"
        webView.evaluateJavaScript(script)

        // For completion mode, just show the content immediately (no header animation)
        if isCompletionMode {
            DispatchQueue.main.async { [weak self] in
                self?.showCompletionContent()
            }
            return
        }

        // Don't check permissions on initial load - wait until user reaches permissions page
        // Just set initial state to false
        let initialScript = """
            window.updatePermissionStatus({
                accessibility: false,
                screenRecording: false
            });
        """
        webView.evaluateJavaScript(initialScript)

        // Trigger the animation to show web content
        DispatchQueue.main.async { [weak self] in
            print("🎬 Starting animation to web view...")
            self?.animateToWebView()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView failed to load: \(error)")
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        print("❌ WebView failed provisional navigation: \(error)")
    }
}

// MARK: - Message Handler

private final class OnboardingMessageHandler: NSObject, WKScriptMessageHandler {
    weak var windowController: OnboardingWindowController?

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
            let action = body["action"] as? String
        else {
            return
        }

        DispatchQueue.main.async {
            switch action {
            case "requestPermissions":
                if let permissionType = body["type"] as? String {
                    self.handleRequestPermissions(type: permissionType)
                }

            case "openLink":
                if let url = body["url"] as? String {
                    self.handleOpenLink(url: url)
                }

            case "completeOnboarding":
                let email = body["email"] as? String
                self.handleCompleteOnboarding(email: email)

            case "track":
                if let event = body["event"] as? String,
                    let props = body["props"] as? [String: Any]
                {
                    self.handleTrack(event: event, props: props)
                }

            case "activateHUD":
                self.handleActivateHUD(body: body)

            case "startPermissionMonitoring":
                self.windowController?.startPermissionStatusTimer()

            case "composeDemo":
                if let input = body["input"] as? String,
                   let tone = body["tone"] as? String {
                    self.handleComposeDemo(input: input, tone: tone)
                }

            case "closeWindow":
                self.windowController?.window?.close()

            case "saveOnboardingProgress":
                // Save onboarding progress early (before screen recording which may restart app)
                let email = body["email"] as? String
                self.handleSaveOnboardingProgress(email: email)

            default:
                print("Unknown onboarding action: \(action)")
            }
        }
    }

    private func handleRequestPermissions(type: String) {
        print("🔑 Request permissions for: \(type)")

        switch type {
        case "accessibility":
            // Open Accessibility preferences
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)

            // Start monitoring for permission changes
            windowController?.startPermissionStatusTimer()

        case "screenRecording":
            // Attempt a screenshot to trigger the system permission dialog
            // The dialog has "Open System Settings" button - user can use that
            print("🎯 Triggering screen recording permission dialog...")
            ScreenshotManager.shared.requestCapture { [weak self] _ in
                // Listen for app becoming active again to check permission
                self?.windowController?.startScreenRecordingMonitor()
            }

        default:
            print("Unknown permission type: \(type)")
        }
    }

    private func handleOpenLink(url: String) {
        if let nsUrl = URL(string: url) {
            NSWorkspace.shared.open(nsUrl)
        }
    }

    /// Save onboarding progress early - called when user completes email/TOS step
    /// This ensures the flag is set before screen recording permission (which may restart the app)
    private func handleSaveOnboardingProgress(email: String?) {
        print("💾 Saving onboarding progress - email: \(email ?? "none")")

        // Accept terms of service
        if let email = email, !email.isEmpty {
            Task {
                do {
                    try await APIClient.shared.acceptTerms(email: email)
                    print("✅ Terms of service accepted for email: \(email)")
                } catch {
                    print("❌ Failed to accept terms: \(error)")
                }
            }
        }

        // Mark onboarding as completed EARLY (before screen recording step)
        UserDefaults.standard.set(true, forKey: "com.foxwiseai.thequickfox.onboardingCompleted")

        // Set flag to show completion screen after potential restart
        UserDefaults.standard.set(true, forKey: "com.foxwiseai.thequickfox.needsPostRestartScreen")

        UserDefaults.standard.synchronize() // Force immediate write to disk

        print("✅ Onboarding progress saved to UserDefaults (with post-restart flag)")
    }

    private func handleCompleteOnboarding(email: String?) {
        print("✅ Onboarding completed")

        // Onboarding flag should already be set by saveOnboardingProgress
        // But set it again just in case
        UserDefaults.standard.set(true, forKey: "com.foxwiseai.thequickfox.onboardingCompleted")

        // Clear the post-restart flag since we completed normally
        UserDefaults.standard.set(false, forKey: "com.foxwiseai.thequickfox.needsPostRestartScreen")

        // Stop the permission status timer
        windowController?.permissionStatusTimer?.invalidate()
        windowController?.permissionStatusTimer = nil

        // Setup the double control detector now that onboarding is complete
        setupDoubleControlDetector()

        // Window stays open - user closes it manually via the Close button
    }

    private func handleCloseWindow() {
        if let window = NSApp.keyWindow, window.title == "TheQuickFox" {
            window.close()
        }
    }

    private func handleTrack(event: String, props: [String: Any]) {
        print("📊 Track event: \(event), props: \(props)")
    }

    @MainActor
    private func handleActivateHUD(body: [String: Any]) {
        guard let modeString = body["mode"] as? String,
              let demoPageContext = body["demoPageContext"] as? String else {
            print("⚠️ Missing required parameters for activateHUD")
            return
        }

        let mode: HUDMode = modeString == "ask" ? .ask : .compose

        print("✅ Activating HUD from JS - mode: \(mode), context: \(demoPageContext)")

        // Create a window highlight for the onboarding window so the animation works
        if let window = NSApp.keyWindow,
           let screen = window.screen {
            // Convert from NSWindow coordinates (bottom-left origin) to CGWindow coordinates (top-left origin)
            let screenHeight = screen.frame.height
            let windowFrame = window.frame

            // CGWindow uses top-left origin, so Y = screenHeight - (NSWindow.y + NSWindow.height)
            let cgY = screenHeight - (windowFrame.origin.y + windowFrame.height)

            // Build a window info dictionary similar to what CGWindowListCopyWindowInfo provides
            let windowInfo: [String: Any] = [
                kCGWindowBounds as String: [
                    "X": windowFrame.origin.x,
                    "Y": cgY,
                    "Width": windowFrame.width,
                    "Height": windowFrame.height
                ],
                kCGWindowOwnerName as String: "TheQuickFox",
                kCGWindowName as String: window.title
            ]

            // Create the highlight that will animate to the HUD
            WindowHighlighter.shared.highlight(windowInfo: windowInfo, duration: 3.0)
        }

        // For logo demo mode, prepare a screenshot of the pretend logo maker
        if demoPageContext == "logo" {
            loadDemoScreenshot()
        }

        HUDManager.shared.presentHUD(initialMode: mode, demoPageContext: demoPageContext)
    }

    @MainActor
    private func loadDemoScreenshot() {
        // Load the pretend-logo-maker.png as a demo screenshot
        let bundle = Bundle.main
        let possiblePaths = [
            bundle.url(forResource: "pretend-logo-maker", withExtension: "png", subdirectory: "Onboarding/Resources"),
            bundle.url(forResource: "pretend-logo-maker", withExtension: "png"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Developer/Xcode/DerivedData")
                .appendingPathComponent("TheQuickFox")
                .appendingPathComponent("Build/Products/Debug/TheQuickFox.app/Contents/Resources/Onboarding/Resources/pretend-logo-maker.png"),
            // Development path
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/TheQuickFox/Onboarding/Resources/pretend-logo-maker.png")
        ]

        for path in possiblePaths.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: path.path) {
                if let image = NSImage(contentsOf: path) {
                    print("✅ Loaded demo screenshot from: \(path.path)")

                    // Create a WindowScreenshot with the demo image
                    let demoScreenshot = WindowScreenshot(
                        image: image,
                        latencyMs: 0,
                        activeInfo: ActiveWindowInfo(
                            bundleID: "com.demo.logomaker",
                            appName: "Pretend Logo Maker",
                            windowTitle: "Logo Design",
                            pid: 0
                        ),
                        windowInfo: [:],
                        scrollViewScreenshots: []
                    )

                    // Update the session with the demo screenshot
                    print("📸 Dispatching demo screenshot to session - size: \(image.size)")
                    AppStore.shared.dispatch(.session(.updateScreenshot(demoScreenshot)))

                    // Verify it was stored
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let storedScreenshot = AppStore.shared.sessionState.cachedScreenshot
                        print("📸 Verification - Screenshot stored: \(storedScreenshot != nil), image: \(storedScreenshot?.image != nil)")
                    }
                    return
                }
            }
        }

        print("⚠️ Could not load demo screenshot pretend-logo-maker.png")
    }

    /// Handle the compose demo request from onboarding
    /// Calls the actual API and streams the result back to JavaScript
    private func handleComposeDemo(input: String, tone: String) {
        print("🎨 Compose demo request - input: '\(input)', tone: \(tone)")

        Task {
            do {
                // Map tone string to ResponseTone
                // Note: "professional" maps to .formal since ResponseTone doesn't have a professional case
                let responseTone: ResponseTone
                switch tone {
                case "friendly":
                    responseTone = .friendly
                case "flirty":
                    responseTone = .flirty
                default:
                    // "professional" and "formal" both map to .formal
                    responseTone = .formal
                }

                // Create minimal app info for demo
                let appInfo = ActiveWindowInfo(
                    bundleID: "com.foxwiseai.thequickfox.onboarding",
                    appName: "TheQuickFox Onboarding",
                    windowTitle: "Getting Started",
                    pid: ProcessInfo.processInfo.processIdentifier
                )

                // Call the compose API
                let stream = try await ComposeClient.shared.stream(
                    mode: .compose,
                    query: input,
                    appInfo: appInfo,
                    contextText: "",
                    screenshot: nil,
                    tone: responseTone
                )

                // Collect all tokens
                var fullResponse = ""
                for try await token in stream {
                    fullResponse += token
                }

                // Send result back to JavaScript
                await MainActor.run {
                    self.sendComposeResult(success: true, text: fullResponse)
                }

            } catch {
                print("❌ Compose demo failed: \(error)")
                await MainActor.run {
                    self.sendComposeResult(success: false, error: error.localizedDescription)
                }
            }
        }
    }

    /// Send compose result back to JavaScript
    @MainActor
    private func sendComposeResult(success: Bool, text: String? = nil, error: String? = nil) {
        var script: String
        if success, let text = text {
            // Escape the text for JavaScript
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            script = "window.handleComposeResult({ success: true, text: \"\(escapedText)\" });"
        } else {
            let escapedError = (error ?? "Unknown error")
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            script = "window.handleComposeResult({ success: false, error: \"\(escapedError)\" });"
        }

        windowController?.evaluateJavaScript(script) { _, jsError in
            if let jsError = jsError {
                print("❌ Failed to send compose result to JS: \(jsError)")
            }
        }
    }
}
