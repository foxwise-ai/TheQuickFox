//
//  HUDViewController.swift
//  TheQuickFox
//
//
//  Thin view controller that manages HUD UI using the centralized AppStore
//

import Cocoa
import Combine
import Down
import SwiftUI
import AVFoundation

// MARK: - Draggable Header View

protocol DraggableHeaderDelegate: AnyObject {
    func headerDidStartDragging(from location: NSPoint)
    func headerDidDrag(to location: NSPoint)
    func headerDidEndDragging()
}

// MARK: - Hover Key Button

final class HoverKeyButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let theme = ThemeManager.shared

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().layer?.backgroundColor = theme.buttonBackgroundHover.cgColor
            self.animator().contentTintColor = theme.buttonTextHover
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().layer?.backgroundColor = theme.buttonBackground.cgColor
            self.animator().contentTintColor = theme.buttonText
        }
    }
}

final class DraggableHeaderView: NSView {
    weak var delegate: DraggableHeaderDelegate?
    private var dragStartLocation: NSPoint = NSPoint.zero

    override func awakeFromNib() {
        super.awakeFromNib()
        wantsLayer = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        delegate?.headerDidStartDragging(from: dragStartLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentLocation = event.locationInWindow
        delegate?.headerDidDrag(to: currentLocation)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.headerDidEndDragging()
    }

}

/// Lightweight view controller that binds HUD UI to centralized state
final class HUDViewController: NSViewController {

    // MARK: - Store

    private let store = AppStore.shared
    private let theme = ThemeManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Components

    private var hudWindow: KeyHUDPanel!
    private var headerView: DraggableHeaderView!
    private var queryTextView: AnimatedCaretTextView!
    private var queryScrollView: NSScrollView!
    private var responseTextView: NSTextView!
    private var responseScrollView: NSScrollView!
    private var metricsHostingView: NSHostingView<MetricsCelebrationView>?
    private var loader: SiriWaveView!
    private var sourceIconView: NSImageView!  // Main icon (app icon or favicon)
    private var browserIconView: NSImageView!  // Secondary browser icon (shown behind favicon)
    private var containerView: NSView!  // Store reference for border animation
    private var footerView: NSView!
    private var enterButton: NSButton!
    private var escButton: NSButton!
    private var enterHintLabel: NSTextField!
    private var modeButtons: [HUDTabButton] = []
    private var toneButtons: [HUDSubTabButton] = []
    private var dragStartLocation: NSPoint = NSPoint.zero
    private var isDragging: Bool = false
    private var queryScrollViewBottomConstraint: NSLayoutConstraint?
    private var responseScrollViewTopConstraint: NSLayoutConstraint?
    private var preserveWindowPosition: Bool = false

    // MARK: - Shortcut Window State
    /// Timer that tracks the shortcut hint window (after HUD opens or mode changes)
    private var shortcutWindowTimer: Timer?
    /// Duration in seconds for which shortcuts are active after HUD opens or mode changes
    private let shortcutWindowDuration: TimeInterval = 3.0
    /// Whether shortcuts are currently active (within the shortcut window)
    private(set) var shortcutsActive: Bool = false

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        setupHUDWindow()
        setupBindings()
        setupThemeBindings()
    }

    // MARK: - Public Interface

    func presentHUD() {
        store.dispatch(.hud(.prepareWindow))
    }

    func hideHUD() {
        store.dispatch(.hud(.hide))
    }

    func submitQuery(_ query: String) {
        store.dispatch(.hud(.submitQuery(query)))
    }

    func changeMode(_ mode: HUDMode) {
        store.dispatch(.hud(.changeMode(mode)))
    }

    func changeTone(_ tone: ResponseTone) {
        store.dispatch(.hud(.changeTone(tone)))
    }

    func submitCurrentQuery() {
        let query = queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            submitQuery(query)
        }
    }

    func navigateHistoryUp() {
        store.dispatch(.hud(.navigateHistoryUp))
    }

    func navigateHistoryDown() {
        store.dispatch(.hud(.navigateHistoryDown))
    }

    func getWindowFrame() -> NSRect? {
        return hudWindow?.frame
    }

    func setWindowFrame(_ frame: NSRect) {
        hudWindow?.setFrame(frame, display: true, animate: false)
    }

    func setPreserveWindowPosition(_ preserve: Bool) {
        preserveWindowPosition = preserve
    }

    // MARK: - Setup

    private func setupHUDWindow() {
        // Create the floating panel - extra padding for source icon overflow
        hudWindow = KeyHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 716, height: 252),  // Extra space for icon overflow
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        hudWindow.level = .floating
        hudWindow.isOpaque = false
        hudWindow.backgroundColor = .clear
        hudWindow.hasShadow = true
        hudWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupHUDContent()
    }

    private func setupHUDContent() {
        // Wrapper view to allow icon overflow - transparent, larger than container
        let wrapperView = NSView()
        wrapperView.wantsLayer = true
        wrapperView.layer?.backgroundColor = NSColor.clear.cgColor
        wrapperView.layer?.masksToBounds = false

        // Actual HUD container - inset to allow icon overflow
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = theme.hudBackground.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = theme.hudBorder.cgColor
        containerView.layer?.masksToBounds = false

        // Create draggable header view
        headerView = DraggableHeaderView()
        headerView.delegate = self

        // Create query text view with scroll view
        queryTextView = AnimatedCaretTextView()
        queryTextView.hudViewController = self  // Set reference for keyboard shortcuts
        queryTextView.backgroundColor = .clear
        queryTextView.textColor = theme.textPrimary
        queryTextView.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        queryTextView.isRichText = false
        queryTextView.delegate = self
        queryTextView.isVerticallyResizable = true
        queryTextView.isHorizontallyResizable = false
        queryTextView.autoresizingMask = [.width]
        queryTextView.textContainer?.widthTracksTextView = true
        queryTextView.textContainer?.lineFragmentPadding = 0
        queryTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        queryTextView.minSize = NSSize(width: 0, height: 0)

        queryScrollView = NSScrollView()
        queryScrollView.documentView = queryTextView
        queryScrollView.hasVerticalScroller = true
        queryScrollView.hasHorizontalScroller = false
        queryScrollView.autohidesScrollers = true
        queryScrollView.backgroundColor = .clear
        queryScrollView.drawsBackground = false

        // Create response text view with scroll view (for ask mode)
        responseTextView = NSTextView()
        responseTextView.backgroundColor = .clear
        responseTextView.textColor = theme.textPrimary
        responseTextView.font = NSFont.systemFont(ofSize: 16)
        responseTextView.isEditable = false
        responseTextView.isSelectable = true
        responseTextView.delegate = self
        responseTextView.isVerticallyResizable = true
        responseTextView.isHorizontallyResizable = false
        responseTextView.autoresizingMask = [.width]
        responseTextView.textContainer?.widthTracksTextView = true
        responseTextView.textContainer?.lineFragmentPadding = 0
        responseTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        responseTextView.minSize = NSSize(width: 0, height: 0)

        // Override cancelOperation to pass ESC to window
        responseTextView.nextResponder = self

        responseScrollView = NSScrollView()
        responseScrollView.documentView = responseTextView
        responseScrollView.hasVerticalScroller = true
        responseScrollView.hasHorizontalScroller = false
        responseScrollView.autohidesScrollers = true
        responseScrollView.backgroundColor = .clear
        responseScrollView.drawsBackground = false
        responseScrollView.isHidden = true

        // Create loader
        loader = SiriWaveView()
        loader.isHidden = true

        // Create mode buttons, source icon, and footer
        setupModeButtons()
        setupToneButtons()
        setupSourceIcon()
        setupFooter()

        // Layout
        setupLayout(containerView: containerView, wrapperView: wrapperView)

        hudWindow.contentView = wrapperView
        hudWindow.contentView?.wantsLayer = true
        hudWindow.contentView?.layer?.masksToBounds = false
    }

    private func setupModeButtons() {
        let respondButton = HUDTabButton()
        respondButton.title = "Compose"
        respondButton.target = self
        respondButton.action = #selector(modeButtonTapped(_:))
        respondButton.tag = 0  // HUDMode.compose
        modeButtons.append(respondButton)

        let askButton = HUDTabButton()
        askButton.title = "Ask"
        askButton.target = self
        askButton.action = #selector(modeButtonTapped(_:))
        askButton.tag = 1  // HUDMode.ask
        modeButtons.append(askButton)
    }

    private func setupToneButtons() {
        let tones = ["Formal", "Friendly", "Flirty"]

        for title in tones {
            let button = HUDSubTabButton()
            button.title = title
            button.target = self
            button.action = #selector(toneButtonTapped(_:))
            toneButtons.append(button)
        }
    }


    private func setupSourceIcon() {
        // Favicon view (behind, rotated) - small badge showing page context
        browserIconView = NSImageView()
        browserIconView.imageScaling = .scaleProportionallyUpOrDown
        browserIconView.wantsLayer = true
        browserIconView.layer?.cornerRadius = 8
        browserIconView.layer?.masksToBounds = true  // Clip to rounded corners
        browserIconView.alphaValue = 0.85

        // Main source icon (front) - app icon or favicon
        sourceIconView = NSImageView()
        sourceIconView.imageScaling = .scaleProportionallyUpOrDown
        sourceIconView.wantsLayer = true
        sourceIconView.layer?.cornerRadius = 16
        // Don't use masksToBounds - it clips the shadow/glow effect
        // App icons are already rounded, and we need shadow to extend beyond bounds
        sourceIconView.layer?.masksToBounds = false
    }

    private func setupFooter() {
        footerView = NSView()
        footerView.wantsLayer = true

        // Helper to create clickable key button with hover effect
        func keyButton(_ text: String, action: Selector) -> HoverKeyButton {
            let button = HoverKeyButton()
            button.title = text
            button.bezelStyle = .rounded
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 3
            button.layer?.backgroundColor = theme.buttonBackground.cgColor
            button.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            button.contentTintColor = theme.buttonText
            button.target = self
            button.action = action
            return button
        }

        // Helper to create hint text
        func hintLabel(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            label.textColor = theme.textTertiary
            label.isBordered = false
            label.drawsBackground = false
            return label
        }

        // Esc button + "to close" hint (first)
        escButton = keyButton("Esc", action: #selector(escButtonTapped))
        let closeHint = hintLabel("to close")

        // Dot separator
        let dotSeparator = NSTextField(labelWithString: "·")
        dotSeparator.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        dotSeparator.textColor = theme.textTertiary
        dotSeparator.isBordered = false
        dotSeparator.drawsBackground = false

        // Enter button + hint (second) - hint text updates based on mode
        enterButton = keyButton("Enter", action: #selector(enterButtonTapped))
        enterHintLabel = hintLabel("to draft")

        // Stack for shortcuts (right-aligned): [Esc] to close · [Enter] to {action}
        let shortcutsStack = NSStackView(views: [escButton, closeHint, dotSeparator, enterButton, enterHintLabel])
        shortcutsStack.orientation = .horizontal
        shortcutsStack.spacing = 4
        shortcutsStack.alignment = .centerY

        // Add to footer
        shortcutsStack.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(shortcutsStack)

        NSLayoutConstraint.activate([
            shortcutsStack.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -8),
            shortcutsStack.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
        ])
    }

    private func setupLayout(containerView: NSView, wrapperView: NSView) {
        // Add button stack views in correct order
        let modeStack = NSStackView(views: modeButtons)
        modeStack.orientation = .horizontal
        modeStack.spacing = 8

        let toneStack = NSStackView(views: toneButtons)
        toneStack.orientation = .horizontal
        toneStack.spacing = 4

        // Add button stacks to header (not the source icon - it goes on container to allow overflow)
        [modeStack, toneStack].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(view)
        }

        // Create metrics celebration view (hidden by default, shown every 10 queries)
        if let metricsData = store.state.metrics.data {
            var celebrationView = MetricsCelebrationView(data: metricsData)
            celebrationView.onDismiss = { [weak self] in
                self?.store.dispatch(.metrics(.hideFromHUD))
            }
            metricsHostingView = NSHostingView(rootView: celebrationView)
            metricsHostingView?.isHidden = !store.state.metrics.showingInHUD
        }

        // Add all main views to container
        var viewsToAdd: [NSView] = [headerView, queryScrollView, responseScrollView, loader, footerView]
        if let metricsView = metricsHostingView {
            viewsToAdd.append(metricsView)
        }

        viewsToAdd.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview($0)
        }

        // Add container to wrapper with inset for icon overflow
        containerView.translatesAutoresizingMaskIntoConstraints = false
        wrapperView.addSubview(containerView)

        // Add source icon (app icon) first - behind
        sourceIconView.translatesAutoresizingMaskIntoConstraints = false
        wrapperView.addSubview(sourceIconView)

        // Add favicon badge on top - in front of app icon
        browserIconView.translatesAutoresizingMaskIntoConstraints = false
        wrapperView.addSubview(browserIconView)

        // Container constraints - inset 64px from top, 76px from right for icon overflow (icon is top-right)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: wrapperView.topAnchor, constant: 64),
            containerView.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor, constant: -76),
            containerView.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor),
        ])

        // Constraints
        NSLayoutConstraint.activate([
            // Header view at top (increase height to accommodate label)
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56),

            // Mode buttons in header
            modeStack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 12),
            modeStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            // Tone buttons on same line, to the right of mode buttons
            toneStack.leadingAnchor.constraint(equalTo: modeStack.trailingAnchor, constant: 24),
            toneStack.centerYAnchor.constraint(equalTo: modeStack.centerYAnchor),

            // Favicon - small badge behind browser icon, tucked in corner
            browserIconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -28),
            browserIconView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            browserIconView.widthAnchor.constraint(equalToConstant: 32),
            browserIconView.heightAnchor.constraint(equalToConstant: 32),

            // Source icon (favicon) - large, in front, overlapping container
            sourceIconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -16),
            sourceIconView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: 32),
            sourceIconView.widthAnchor.constraint(equalToConstant: 72),
            sourceIconView.heightAnchor.constraint(equalToConstant: 72),

            // Footer at bottom
            footerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            footerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            footerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 0),
            footerView.heightAnchor.constraint(equalToConstant: 32),

            // Query scroll view (anchored below header)
            queryScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 0),
            queryScrollView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 16),
            queryScrollView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -16),

            // Response scroll view (leading/trailing only - vertical constraints managed dynamically)
            responseScrollView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 16),
            responseScrollView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -16),
            responseScrollView.bottomAnchor.constraint(
                equalTo: footerView.topAnchor, constant: -4),

            // Loader centered in query scroll view
            loader.centerXAnchor.constraint(equalTo: queryScrollView.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: queryScrollView.centerYAnchor),
            loader.widthAnchor.constraint(equalToConstant: 120),
            loader.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Set up dynamic constraints for query/response split
        // Default: query fills to footer (response hidden)
        queryScrollViewBottomConstraint = queryScrollView.bottomAnchor.constraint(
            equalTo: footerView.topAnchor, constant: -4)
        queryScrollViewBottomConstraint?.isActive = true

        // Response top anchored below query with fixed query height when visible
        responseScrollViewTopConstraint = responseScrollView.topAnchor.constraint(
            equalTo: headerView.bottomAnchor, constant: 52)  // Fixed height for query area
        responseScrollViewTopConstraint?.isActive = false

        // Add metrics celebration view constraints if it exists
        if let metricsView = metricsHostingView {
            NSLayoutConstraint.activate([
                metricsView.topAnchor.constraint(
                    equalTo: queryScrollView.bottomAnchor, constant: 8),
                metricsView.leadingAnchor.constraint(
                    equalTo: containerView.leadingAnchor, constant: 16),
                metricsView.trailingAnchor.constraint(
                    equalTo: containerView.trailingAnchor, constant: -16),
                metricsView.bottomAnchor.constraint(
                    equalTo: footerView.topAnchor, constant: -8),
            ])
        }
    }

    // MARK: - Mouse Tracking

    // MARK: - Actions

    func handleEscapeKey() {
        store.dispatch(.hud(.hideWithReason(.escape)))
    }

    @objc private func enterButtonTapped() {
        submitCurrentQuery()
    }

    @objc private func escButtonTapped() {
        store.dispatch(.hud(.hideWithReason(.escape)))
    }

    @objc private func modeButtonTapped(_ sender: HUDTabButton) {
        let mode: HUDMode = sender.tag == 0 ? .compose : .ask
        store.dispatch(.hud(.changeMode(mode)))
    }

    @objc private func toneButtonTapped(_ sender: HUDSubTabButton) {
        let toneMap: [String: ResponseTone] = [
            "Formal": .formal,
            "Friendly": .friendly,
            "Flirty": .flirty,
        ]

        guard let tone = toneMap[sender.title] else {
            print("⚠️ Unknown tone button: \(sender.title)")
            return
        }

        store.dispatch(.hud(.changeTone(tone)))
    }

    // MARK: - Shortcut Window Management

    /// Starts the shortcut window timer - shortcuts are active for a few seconds after HUD opens or mode changes
    private func startShortcutWindow() {
        // Cancel any existing timer
        shortcutWindowTimer?.invalidate()

        // Activate shortcuts
        shortcutsActive = true
        updateShortcutHints()
        print("⌨️ Shortcut window started, shortcutsActive = \(shortcutsActive)")

        // Start timer to deactivate shortcuts
        shortcutWindowTimer = Timer.scheduledTimer(withTimeInterval: shortcutWindowDuration, repeats: false) { [weak self] _ in
            self?.endShortcutWindow()
        }
    }

    /// Ends the shortcut window - shortcuts will no longer work, keys type normally
    private func endShortcutWindow() {
        shortcutWindowTimer?.invalidate()
        shortcutWindowTimer = nil
        shortcutsActive = false
        updateShortcutHints()
        print("⌨️ Shortcut window ended, shortcutsActive = \(shortcutsActive)")
    }

    /// Updates the visibility of shortcut hints on buttons based on current mode and shortcut state
    private func updateShortcutHints() {
        let currentMode = store.state.hud.mode

        // Tab shortcut on mode buttons:
        // - If in Ask mode: show Tab hint on Compose/Code button (index 0)
        // - If in Compose/Code mode: show Tab hint on Ask button (index 1)
        if modeButtons.count >= 2 {
            let composeCodeButton = modeButtons[0]
            let askButton = modeButtons[1]

            // Set shortcut hints
            composeCodeButton.shortcutHint = "⇥"
            askButton.shortcutHint = "⇥"

            // Show hint on the non-active button only
            composeCodeButton.shortcutHintVisible = shortcutsActive && currentMode == .ask
            askButton.shortcutHintVisible = shortcutsActive && (currentMode == .compose || currentMode == .code)
        }

        // Number shortcuts (1, 2, 3) on tone buttons - only in Compose mode, only on non-selected tones
        let currentTone = store.state.hud.tone
        let toneOrder: [ResponseTone] = [.formal, .friendly, .flirty]
        for (index, button) in toneButtons.enumerated() {
            button.shortcutHint = "\(index + 1)"
            let isSelectedTone = index < toneOrder.count && toneOrder[index] == currentTone
            button.shortcutHintVisible = shortcutsActive && currentMode == .compose && !isSelectedTone
        }
    }

    /// Handles Tab key press if within the shortcut window. Returns true if handled.
    func handleTabKeyIfInShortcutWindow() -> Bool {
        guard shortcutsActive else { return false }

        let currentMode = store.state.hud.mode

        // Toggle between Ask and Compose/Code modes
        if currentMode == .ask {
            // Switch to Compose (or Code if that was the previous mode)
            // For simplicity, we'll just go to Compose
            store.dispatch(.hud(.changeMode(.compose)))
        } else {
            // Switch to Ask mode
            store.dispatch(.hud(.changeMode(.ask)))
        }

        // Restart shortcut window after mode change
        startShortcutWindow()

        return true
    }

    /// Handles 1/2/3 key press for tone shortcuts if within the shortcut window. Returns true if handled.
    func handleToneShortcutIfInShortcutWindow(keyCode: UInt16) -> Bool {
        guard shortcutsActive else { return false }

        // Only works in Compose mode
        let currentMode = store.state.hud.mode
        guard currentMode == .compose else { return false }

        // Map key codes to tones: 18='1', 19='2', 20='3'
        let tones: [UInt16: ResponseTone] = [
            18: .formal,   // 1
            19: .friendly, // 2
            20: .flirty    // 3
        ]

        guard let tone = tones[keyCode] else { return false }

        store.dispatch(.hud(.changeTone(tone)))

        // Restart shortcut window after tone change
        startShortcutWindow()

        return true
    }

    // MARK: - State Binding

    private func setupBindings() {
        // Bind to HUD state changes
        store.hudStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hudState in
                self?.updateUI(for: hudState)
            }
            .store(in: &cancellables)

        // Bind to session screenshot changes (separate from HUD state to avoid redundant updates)
        store.sessionStatePublisher
            .map(\.cachedScreenshot)
            .removeDuplicates { $0?.latencyMs == $1?.latencyMs && $0?.activeInfo.bundleID == $1?.activeInfo.bundleID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSourceIcon()
            }
            .store(in: &cancellables)
    }

    private func setupThemeBindings() {
        // Observe theme changes and update UI accordingly
        theme.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyTheme()
            }
            .store(in: &cancellables)
    }

    private func applyTheme() {
        // Update container background and border
        containerView?.layer?.backgroundColor = theme.hudBackground.cgColor
        containerView?.layer?.borderColor = theme.hudBorder.cgColor

        // Update text colors
        queryTextView?.textColor = theme.textPrimary
        responseTextView?.textColor = theme.textPrimary

        // Update footer hint labels
        enterHintLabel?.textColor = theme.textTertiary

        // Update footer buttons
        escButton?.layer?.backgroundColor = theme.buttonBackground.cgColor
        escButton?.contentTintColor = theme.buttonText
        enterButton?.layer?.backgroundColor = theme.buttonBackground.cgColor
        enterButton?.contentTintColor = theme.buttonText

        // Notify animated caret text view of theme change
        queryTextView?.setNeedsDisplay(queryTextView?.bounds ?? .zero)
    }

    private func updateUI(for hudState: HUDState) {
        // Window visibility
        if hudState.isVisible {
            showWindow()
        } else {
            hideWindow()
        }

        // Mode buttons
        updateModeButtons(selectedMode: hudState.mode, canRespond: hudState.canRespond)

        // Footer hint based on mode
        updateFooterHint(for: hudState.mode)

        // Tone buttons
        updateToneButtons(selectedTone: hudState.tone, mode: hudState.mode)

        // Text and response content
        updateTextContent(hudState: hudState)

        // UI state
        updateUIState(hudState: hudState)

        // Window size
        updateWindowSize(hudState: hudState)
    }

    private func showWindow() {
        guard !hudWindow.isVisible else {
            print("⚠️ HUD window already visible, skipping showWindow")
            return
        }

        // Only reposition if we're not preserving the position
        if !preserveWindowPosition {
            // Get the screen containing the active window
            let targetScreen = getActiveWindowScreen() ?? NSScreen.main ?? NSScreen.screens[0]

            // Debug logging for multi-monitor setup
            if NSScreen.screens.count > 1 {
                print("🖥️ Multi-monitor detected: \(NSScreen.screens.count) screens")
                if let activeScreen = getActiveWindowScreen() {
                    print("🎯 Active window is on screen: \(activeScreen.localizedName)")
                } else {
                    print("⚠️ Could not determine active window screen, using main screen")
                }
            }

            // Center on the target screen
            let screenFrame = targetScreen.visibleFrame
            let windowSize = hudWindow.frame.size
            let x = screenFrame.midX - windowSize.width / 2
            let y = screenFrame.midY - windowSize.height / 2
            hudWindow.setFrame(
                NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height),
                display: true)
        }

        // Reset the flag after use
        preserveWindowPosition = false

        hudWindow.makeKeyAndOrderFront(nil)
        hudWindow.makeFirstResponder(queryTextView)

        // Start shortcut window when HUD opens
        startShortcutWindow()

        // Notify observers that HUD appeared (used by completion screen)
        print("📣 Posting hudDidAppear notification")
        NotificationCenter.default.post(name: .hudDidAppear, object: nil)
    }

    private func hideWindow() {
        hudWindow.orderOut(nil)
        // End shortcut window when HUD closes
        endShortcutWindow()
    }

    private func updateFooterHint(for mode: HUDMode) {
        switch mode {
        case .compose:
            enterHintLabel.stringValue = "to draft"
        case .ask:
            enterHintLabel.stringValue = "to ask"
        case .code:
            enterHintLabel.stringValue = "to generate"
        }
    }

    private func updateModeButtons(selectedMode: HUDMode, canRespond: Bool) {
        let firstButton = modeButtons[0]
        firstButton.isEnabled = true

        if selectedMode == .code {
            firstButton.title = "Code"
            firstButton.state = NSControl.StateValue.on
            updateButtonVisualState(firstButton, isDisconnected: false)
        } else if selectedMode == .compose {
            firstButton.title = "Compose"
            firstButton.state = NSControl.StateValue.on
            updateButtonVisualState(firstButton, isDisconnected: false)
        } else {
            firstButton.state = NSControl.StateValue.off
            firstButton.title = "Compose"
            updateButtonVisualState(firstButton, isDisconnected: false)
        }

        modeButtons[1].state =
            selectedMode == .ask ? NSControl.StateValue.on : NSControl.StateValue.off

        // Update shortcut hints when mode changes
        updateShortcutHints()
    }

    private func updateButtonVisualState(_ button: NSButton, isDisconnected: Bool) {
        button.wantsLayer = true

        if isDisconnected {
            // Add dotted border effect using shadow instead of dashed line
            button.layer?.borderWidth = 1.5
            button.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.3).cgColor
            button.layer?.shadowColor = NSColor.systemOrange.cgColor
            button.layer?.shadowOffset = CGSize(width: 0, height: 0)
            button.layer?.shadowRadius = 2
            button.layer?.shadowOpacity = 0.3
            button.alphaValue = 0.6

            // Add explanatory tooltip
            button.toolTip = "Click in a text field first to enable Compose mode"
        } else {
            // Reset to normal appearance
            button.layer?.borderWidth = 0
            button.layer?.borderColor = nil
            button.layer?.shadowOpacity = 0
            button.alphaValue = 1.0

            // Remove tooltip when connected
            button.toolTip = nil
        }
    }

    private func updateToneButtons(selectedTone: ResponseTone, mode: HUDMode) {
        // Hide tone buttons in Ask mode or Code mode
        toneButtons.forEach { $0.isHidden = (mode == .ask || mode == .code) }

        if mode == .compose {
            // First, turn off all tone buttons
            toneButtons.forEach { $0.state = NSControl.StateValue.off }

            // Then turn on the selected one
            for button in toneButtons {
                let toneMap: [String: ResponseTone] = [
                    "Formal": .formal,
                    "Friendly": .friendly,
                    "Flirty": .flirty,
                ]

                if toneMap[button.title] == selectedTone {
                    button.state = NSControl.StateValue.on
                    break
                }
            }
        }

        // Update placeholder text based on tone and mode
        updatePlaceholder(for: mode, tone: selectedTone)
    }

    private func updatePlaceholder(for mode: HUDMode, tone: ResponseTone) {
        let placeholder: String

        switch mode {
        case .compose:
            switch tone {
            case .formal:
                placeholder = "What do you want to say? (we'll make it formal)"
            case .friendly:
                placeholder = "What do you want to say? (we'll make it friendly)"
            case .flirty:
                placeholder = "What do you want to say? (we'll make it flirty)"
            }
        case .ask:
            placeholder = "Ask a question about what's on your screen"
        case .code:
            placeholder = "Pretend you're writing code in your own words"
        }

        queryTextView.placeholderString = placeholder
    }

    private func updateTextContent(hudState: HUDState) {
        // Update query text
        if queryTextView.string != hudState.currentQuery {
            print("🔄 Updating query text from '\(queryTextView.string)' to '\(hudState.currentQuery)'")
            queryTextView.string = hudState.currentQuery
        }

        // Update response content with markdown rendering
        switch hudState.response {
        case .idle:
            responseTextView.string = ""
        case .failed(let error):
            // Display error message in response area
            // Note: error is already a String in ResponseState.failed
            responseTextView.string = "⚠️ \(error)"
            responseTextView.textColor = NSColor.systemRed
        case .streaming(let content), .completed(let content):
            renderMarkdownContent(content)
            responseTextView.textColor = NSColor.labelColor // Reset to normal color
        }
    }

    private func renderMarkdownContent(_ content: String) {
        do {
            // Content already has citations inserted by the reducer when grounding metadata arrived
            // Just render the markdown as-is
            let down = Down(markdownString: content)
            let html = try down.toHTML()

            // Wrap HTML with our custom CSS
            let styledHTML = """
                <html>
                <head>
                <style>
                \(customMarkdownStylesheet())
                </style>
                </head>
                <body>
                \(html)
                </body>
                </html>
                """

            // Convert HTML to NSAttributedString
            guard let htmlData = styledHTML.data(using: String.Encoding.utf8) else {
                responseTextView.string = content
                return
            }

            let attributedString = try NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )

            responseTextView.textStorage?.setAttributedString(attributedString)
        } catch {
            // Fallback to plain text if markdown rendering fails
            responseTextView.string = content
        }
    }

    private func customMarkdownStylesheet() -> String {
        let textColor = theme.hexString(for: theme.textPrimary)
        let textSecondary = theme.rgbaString(for: theme.textSecondary)
        let codeInlineBg = theme.rgbaString(for: theme.codeInlineBackground)
        let codeBlockBg = theme.rgbaString(for: theme.codeBlockBackground)
        let codeBlockBorder = theme.rgbaString(for: theme.codeBlockBorder)
        let codeTextColor = theme.hexString(for: theme.codeText)
        let linkColor = theme.hexString(for: theme.linkColor)
        let blockquoteBorderColor = theme.hexString(for: theme.blockquoteBorder)
        let blockquoteBgColor = theme.rgbaString(for: theme.blockquoteBackground)
        let tableBorderColor = theme.rgbaString(for: theme.tableBorder)
        let tableHeaderBgColor = theme.rgbaString(for: theme.tableHeaderBackground)
        let separatorColor = theme.rgbaString(for: theme.separator)

        return """
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif;
                font-size: 16px;
                line-height: 1.5;
                color: \(textColor);
                background-color: transparent;
                margin: 0;
                padding: 0;
            }

            h1, h2, h3, h4, h5, h6 {
                color: \(textColor);
                margin-top: 1.2em;
                margin-bottom: 0.6em;
                font-weight: 600;
            }
            h1 { font-size: 22px; }
            h2 { font-size: 20px; }
            h3 { font-size: 18px; }
            h4 { font-size: 16px; font-weight: 700; }

            p {
                margin: 0 0 1em 0;
                color: \(textColor);
            }

            code {
                background-color: \(codeInlineBg);
                color: \(codeTextColor);
                padding: 2px 6px;
                border-radius: 4px;
                font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', monospace;
                font-size: 14px;
                border: 1px solid \(codeBlockBorder);
            }

            pre {
                background-color: \(codeBlockBg);
                border: 1px solid \(codeBlockBorder);
                border-radius: 8px;
                padding: 16px;
                overflow-x: auto;
                margin: 1.2em 0;
                line-height: 1.4;
            }

            pre code {
                background-color: transparent;
                border: none;
                padding: 0;
                color: \(codeTextColor);
                font-size: 14px;
            }

            ul, ol {
                margin: 1em 0;
                padding-left: 1.8em;
                color: \(textColor);
            }

            li {
                margin-bottom: 0.4em;
                color: \(textColor);
            }

            blockquote {
                border-left: 4px solid \(blockquoteBorderColor);
                margin: 1.2em 0;
                padding: 0.8em 0 0.8em 1.2em;
                background-color: \(blockquoteBgColor);
                border-radius: 0 6px 6px 0;
                color: \(textSecondary);
                font-style: italic;
            }

            strong {
                font-weight: 700;
                color: \(textColor);
            }

            em {
                font-style: italic;
                color: \(textSecondary);
            }

            a {
                color: \(linkColor);
                text-decoration: none;
                border-bottom: 1px solid \(blockquoteBgColor);
            }

            a:hover {
                color: \(linkColor);
                border-bottom-color: \(blockquoteBorderColor);
            }

            table {
                border-collapse: collapse;
                width: 100%;
                margin: 1em 0;
                border: 1px solid \(tableBorderColor);
            }

            th, td {
                border: 1px solid \(tableBorderColor);
                padding: 8px 12px;
                text-align: left;
                color: \(textColor);
            }

            th {
                background-color: \(tableHeaderBgColor);
                font-weight: 600;
            }

            hr {
                border: none;
                border-top: 1px solid \(separatorColor);
                margin: 2em 0;
            }
            """
    }

    private func updateUIState(hudState: HUDState) {
        // Text editability
        queryTextView.isEditable = hudState.ui.textIsEditable

        // Loader visibility and animation
        if hudState.ui.loaderIsVisible {
            loader.isHidden = false
            loader.start()
            queryTextView.isLoaderVisible = true  // Notify text view to hide placeholder
        } else {
            loader.stop()
            loader.isHidden = true
            queryTextView.isLoaderVisible = false  // Allow placeholder to show if text is empty
        }

        // Response container visibility and layout
        let showingMetrics = store.state.metrics.showingInHUD
        let showResponse = hudState.ui.responseContainerIsVisible && !showingMetrics
        responseScrollView.isHidden = !showResponse
        metricsHostingView?.isHidden = !showingMetrics

        // Toggle constraints based on response visibility
        if showResponse {
            // Show response: fix query height, activate response top
            queryScrollViewBottomConstraint?.isActive = false
            responseScrollViewTopConstraint?.isActive = true
        } else {
            // Hide response: query fills to footer
            responseScrollViewTopConstraint?.isActive = false
            queryScrollViewBottomConstraint?.isActive = true
        }

        // Recreate metrics view if it should be shown (to refresh onDismiss callback and restart timer)
        if showingMetrics, let metricsData = store.state.metrics.data {
            var celebrationView = MetricsCelebrationView(data: metricsData)
            celebrationView.onDismiss = { [weak self] in
                self?.store.dispatch(.metrics(.hideFromHUD))
            }
            metricsHostingView?.rootView = celebrationView
        }

        // Border animation
        if hudState.ui.borderAnimationActive {
            startBorderAnimation()
        } else {
            stopBorderAnimation()
        }

        // Animate to HUD
        if hudState.ui.shouldAnimateToHUD {
            animateHighlightToHUD()
            // Reset the flag immediately after triggering
            store.dispatch(.hud(.resetAnimateToHUD))
        }
    }

    private func updateSourceIcon() {
        // Get screenshot and app icon from session state
        let cachedScreenshot = store.sessionState.cachedScreenshot

        guard let activeInfo = cachedScreenshot?.activeInfo,
              let bundleID = activeInfo.bundleID else {
            sourceIconView.image = nil
            browserIconView.image = nil
            browserIconView.isHidden = true
            return
        }

        // Get app icon
        var appIcon: NSImage? = nil
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        }

        // Show app icon immediately
        sourceIconView.image = appIcon
        sourceIconView.alphaValue = 1.0

        // Check if it's a browser
        let browserBundleIDs = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "org.mozilla.firefox",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "company.thebrowser.Browser"  // Arc
        ]

        guard browserBundleIDs.contains(bundleID) else {
            browserIconView.isHidden = true
            return
        }

        // Hide old favicon while we fetch new one
        browserIconView.isHidden = true

        // Do URL extraction in background (Accessibility API can be slow)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let urlString = BrowserURLExtractor.extractURL(from: activeInfo),
                  let url = URL(string: urlString),
                  let host = url.host,
                  host != "localhost" && host != "127.0.0.1" && !host.hasSuffix(".local")
            else { return }

            print("🖼️ [SourceIcon] Fetching favicon for \(host)")

            // FaviconFetcher has its own cache - will return instantly if cached
            FaviconFetcher.shared.fetchFavicon(for: url, size: 128) { [weak self] favicon in
                guard let self = self, let favicon = favicon else {
                    print("🖼️ [SourceIcon] No favicon received")
                    return
                }

                print("🖼️ [SourceIcon] Showing favicon for \(host)")

                self.browserIconView.image = favicon
                self.browserIconView.isHidden = false
                self.browserIconView.alphaValue = 0
                self.browserIconView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                self.browserIconView.layer?.transform = CATransform3DMakeRotation(-0.15, 0, 0, 1)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.browserIconView.animator().alphaValue = 0.85
                }
            }
        }
    }


    private func updateWindowSize(hudState: HUDState) {
        let targetHeight = hudState.ui.panelHeight
        let currentFrame = hudWindow.frame

        // Only resize for significant height changes
        if abs(currentFrame.height - targetHeight) > 10 {
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y - (targetHeight - currentFrame.height),
                width: currentFrame.width,
                height: targetHeight
            )

            // Animate expansion in Ask mode when response comes in, otherwise no animation
            let shouldAnimate = hudState.mode == .ask && hudState.ui.responseContainerIsVisible

            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    hudWindow.animator().setFrame(newFrame, display: true)
                }
            } else {
                hudWindow.setFrame(newFrame, display: true, animate: false)
            }
        }
    }

    private func startBorderAnimation() {
        // Simple rainbow border animation on the container (not wrapper)
        guard let borderLayer = containerView?.layer else { return }

        let colorAnimation = CAKeyframeAnimation(keyPath: "borderColor")
        colorAnimation.values = [
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemPink.cgColor,
            NSColor.systemRed.cgColor,
            NSColor.systemOrange.cgColor,
            NSColor.systemYellow.cgColor,
            NSColor.systemGreen.cgColor,
            NSColor.systemBlue.cgColor,
        ]
        colorAnimation.duration = 2.0
        colorAnimation.repeatCount = .infinity

        borderLayer.add(colorAnimation, forKey: "rainbowBorder")

        // Add matching glow animation to source icon
        startIconGlowAnimation()
    }

    private func stopBorderAnimation() {
        containerView?.layer?.removeAnimation(forKey: "rainbowBorder")
        containerView?.layer?.borderColor = theme.hudBorder.cgColor

        // Remove icon glow
        stopIconGlowAnimation()
    }

    private func startIconGlowAnimation() {
        guard let iconLayer = sourceIconView?.layer else { return }

        // Enable shadow
        iconLayer.shadowOpacity = 0.8
        iconLayer.shadowRadius = 14
        iconLayer.shadowOffset = CGSize(width: 0, height: 0)

        // Animate shadow color through rainbow
        let shadowColorAnimation = CAKeyframeAnimation(keyPath: "shadowColor")
        shadowColorAnimation.values = [
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemPink.cgColor,
            NSColor.systemRed.cgColor,
            NSColor.systemOrange.cgColor,
            NSColor.systemYellow.cgColor,
            NSColor.systemGreen.cgColor,
            NSColor.systemBlue.cgColor,
        ]
        shadowColorAnimation.duration = 2.0
        shadowColorAnimation.repeatCount = .infinity

        iconLayer.add(shadowColorAnimation, forKey: "rainbowGlow")
    }

    private func stopIconGlowAnimation() {
        guard let iconLayer = sourceIconView?.layer else { return }
        iconLayer.removeAnimation(forKey: "rainbowGlow")
        iconLayer.shadowOpacity = 0
    }

    private func animateHighlightToHUD() {
        // Calculate target bounds instead of using current frame (which may be unpositioned)
        let targetBounds = calculateHUDTargetBounds()

        // Animate the window highlight to the HUD position (fast)
        WindowHighlighter.shared.animateToHUD(hudBounds: targetBounds, duration: 0.3) {
            // Animation complete - reset the state flag
            // This will prevent the animation from re-triggering
        }
    }

    private func calculateHUDTargetBounds() -> NSRect {
        // Get the screen containing the active window
        let targetScreen = getActiveWindowScreen() ?? NSScreen.main ?? NSScreen.screens[0]

        let screenFrame = targetScreen.visibleFrame
        let windowSize = hudWindow.frame.size
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2

        return NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
    }

    /// Determines which screen contains the active window based on cached screenshot info
    private func getActiveWindowScreen() -> NSScreen? {
        // Try to get window bounds from the cached screenshot
        guard let windowInfo = store.sessionState.cachedScreenshot?.windowInfo,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat,
              let width = boundsDict["Width"] as? CGFloat,
              let height = boundsDict["Height"] as? CGFloat else {
            return nil
        }

        // CoreGraphics window bounds are in global coordinates with top-left origin
        let cgWindowRect = CGRect(x: x, y: y, width: width, height: height)

        // Find the screen that contains the window's center point
        let windowCenter = CGPoint(x: cgWindowRect.midX, y: cgWindowRect.midY)

        // Convert from CoreGraphics coordinates to NSScreen coordinates
        // CG uses top-left origin, NS uses bottom-left origin
        // We need to get the full desktop bounds to do the conversion
        var fullDesktopHeight: CGFloat = 0
        for screen in NSScreen.screens {
            fullDesktopHeight = max(fullDesktopHeight, screen.frame.maxY)
        }

        let nsWindowCenter = NSPoint(x: windowCenter.x, y: fullDesktopHeight - windowCenter.y)

        // Find the screen that contains this point
        for screen in NSScreen.screens {
            if screen.frame.contains(nsWindowCenter) {
                return screen
            }
        }

        // If no screen contains the center point (edge case),
        // find the screen with the most overlap
        var bestScreen: NSScreen?
        var maxOverlap: CGFloat = 0

        // Convert the entire window rect to NS coordinates
        let nsWindowRect = NSRect(
            x: cgWindowRect.origin.x,
            y: fullDesktopHeight - cgWindowRect.origin.y - cgWindowRect.height,
            width: cgWindowRect.width,
            height: cgWindowRect.height
        )

        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(nsWindowRect)
            let overlapArea = intersection.width * intersection.height

            if overlapArea > maxOverlap {
                maxOverlap = overlapArea
                bestScreen = screen
            }
        }

        return bestScreen
    }
}

// MARK: - DraggableHeaderDelegate

extension HUDViewController: DraggableHeaderDelegate {
    func headerDidStartDragging(from location: NSPoint) {
        dragStartLocation = location
        isDragging = true
    }

    func headerDidDrag(to location: NSPoint) {
        guard isDragging else { return }

        let deltaX = location.x - dragStartLocation.x
        let deltaY = location.y - dragStartLocation.y

        let currentFrame = hudWindow.frame
        let newOrigin = NSPoint(
            x: currentFrame.origin.x + deltaX,
            y: currentFrame.origin.y + deltaY
        )

        hudWindow.setFrameOrigin(newOrigin)
    }

    func headerDidEndDragging() {
        isDragging = false
    }
}

// MARK: - NSTextViewDelegate

extension HUDViewController: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        store.dispatch(.hud(.updateQuery(textView.string)))
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Submit on Enter
            let query = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                store.dispatch(.hud(.submitQuery(query)))
            }
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Hide on Escape with intentional close reason
            store.dispatch(.hud(.hideWithReason(.escape)))
            return true
        }

        return false
    }
}
