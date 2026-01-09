//
//  TypeHintToast.swift
//  TheQuickFox
//
//  A beautiful, non-intrusive toast that hints users to try TheQuickFox
//  when extended typing or struggle is detected.
//

import AVKit
import Cocoa
import Combine

final class TypeHintToast: NSPanel {

    // MARK: - UI Components

    private let blurView = NSVisualEffectView()
    private let containerView = NSView()
    private let iconContainer = NSView()
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var loopCount = 0
    private let maxLoops = 2
    private let textStack = NSStackView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()
    private let shortcutBadge = NSView()
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let dismissButton = NSButton()

    // MARK: - Theme

    private let theme = ThemeManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Properties

    var onDismiss: (() -> Void)?
    var onActivate: (() -> Void)?

    private var autoDismissTimer: Timer?
    private let autoDismissDelay: TimeInterval = 6.0

    // Track mouse for interaction
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        setupUI()
        setupThemeBinding()
        setupClickHandler()
    }

    // MARK: - Setup

    private func setupUI() {
        guard let contentView = contentView else { return }

        // Blur background (glassmorphism)
        blurView.blendingMode = .behindWindow
        blurView.material = theme.isDarkMode ? .hudWindow : .menu
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 16
        blurView.layer?.masksToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blurView)

        // Container with subtle border
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 16
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = (theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)).cgColor
        containerView.layer?.masksToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Drop shadow
        contentView.wantsLayer = true
        contentView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        contentView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        contentView.layer?.shadowRadius = 16
        contentView.layer?.shadowOpacity = 1

        // Icon container for video
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 10
        iconContainer.layer?.masksToBounds = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconContainer)

        // Setup looping video player
        setupVideoPlayer()

        // Text stack
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textStack)

        // Message label - random playful message
        let messages = [
            "Let the fox handle this one",
            "Stuck? I got you",
            "Need a paw with that?",
            "Writer's block? Not anymore",
            "Let me take it from here",
            "I can help with that",
            "Looks like you could use a fox",
            "Allow me",
            "Tag me in",
            "Fox to the rescue"
        ]
        messageLabel.stringValue = messages.randomElement() ?? messages[0]
        messageLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        messageLabel.textColor = theme.textPrimary
        messageLabel.isBordered = false
        messageLabel.isEditable = false
        messageLabel.drawsBackground = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(messageLabel)

        // Shortcut container (horizontal stack)
        shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(shortcutContainer)

        // Keyboard shortcut badge
        shortcutBadge.wantsLayer = true
        shortcutBadge.layer?.cornerRadius = 4
        shortcutBadge.layer?.backgroundColor = (theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.1)
            : NSColor.black.withAlphaComponent(0.06)).cgColor
        shortcutBadge.layer?.borderWidth = 0.5
        shortcutBadge.layer?.borderColor = (theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.15)
            : NSColor.black.withAlphaComponent(0.1)).cgColor
        shortcutBadge.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.addSubview(shortcutBadge)

        // Shortcut label inside badge
        shortcutLabel.stringValue = "Control"
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        shortcutLabel.textColor = theme.textSecondary
        shortcutLabel.isBordered = false
        shortcutLabel.isEditable = false
        shortcutLabel.drawsBackground = false
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutBadge.addSubview(shortcutLabel)

        // "x2" indicator after badge
        let timesLabel = NSTextField(labelWithString: " x2")
        timesLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        timesLabel.textColor = theme.textSecondary.withAlphaComponent(0.8)
        timesLabel.isBordered = false
        timesLabel.isEditable = false
        timesLabel.drawsBackground = false
        timesLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.addSubview(timesLabel)

        // Dismiss button
        dismissButton.title = ""
        dismissButton.bezelStyle = .roundRect
        dismissButton.isBordered = false
        let xConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?
            .withSymbolConfiguration(xConfig)
        dismissButton.contentTintColor = theme.textSecondary.withAlphaComponent(0.5)
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)
        dismissButton.alphaValue = 0.6
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dismissButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Blur fills panel
            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Container fills panel
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Icon container (left side)
            iconContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),

            // Text stack
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: dismissButton.leadingAnchor, constant: -12),

            // Shortcut container height
            shortcutContainer.heightAnchor.constraint(equalToConstant: 18),

            // Shortcut badge
            shortcutBadge.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor),
            shortcutBadge.centerYAnchor.constraint(equalTo: shortcutContainer.centerYAnchor),
            shortcutBadge.heightAnchor.constraint(equalToConstant: 18),

            // Shortcut label inside badge
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutBadge.leadingAnchor, constant: 6),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor, constant: -6),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutBadge.centerYAnchor),

            // Times label after badge
            timesLabel.leadingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor, constant: 2),
            timesLabel.centerYAnchor.constraint(equalTo: shortcutContainer.centerYAnchor),

            // Dismiss button (right side)
            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            dismissButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 20),
            dismissButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func setupVideoPlayer() {
        guard let videoURL = Bundle.main.url(forResource: "fox-animation-small", withExtension: "mp4") else {
            print("⚠️ Fox animation video not found in bundle")
            return
        }

        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = true
        self.player = avPlayer

        // Observe when video ends to loop
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(videoDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Create and configure player layer
        let layer = AVPlayerLayer(player: avPlayer)
        layer.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        layer.videoGravity = .resizeAspectFill
        layer.cornerRadius = 10
        layer.masksToBounds = true
        iconContainer.layer?.addSublayer(layer)
        self.playerLayer = layer
    }

    @objc private func videoDidEnd() {
        loopCount += 1
        if loopCount < maxLoops {
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func startVideoPlayback() {
        loopCount = 0
        player?.seek(to: .zero)
        player?.play()
    }

    private func stopVideoPlayback() {
        player?.pause()
        loopCount = 0
    }

    private func setupThemeBinding() {
        theme.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyTheme()
            }
            .store(in: &cancellables)
    }

    private func applyTheme() {
        blurView.material = theme.isDarkMode ? .hudWindow : .menu

        containerView.layer?.borderColor = (theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)).cgColor

        shortcutBadge.layer?.backgroundColor = (theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.1)
            : NSColor.black.withAlphaComponent(0.06)).cgColor
        shortcutBadge.layer?.borderColor = (theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.15)
            : NSColor.black.withAlphaComponent(0.1)).cgColor

        messageLabel.textColor = theme.textPrimary
        shortcutLabel.textColor = theme.textSecondary
        dismissButton.contentTintColor = theme.textSecondary.withAlphaComponent(0.5)
    }

    private func setupClickHandler() {
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(toastClicked))
        containerView.addGestureRecognizer(clickGesture)
    }

    // MARK: - Tracking Area for Hover

    private func setupTrackingArea() {
        if let existing = trackingArea {
            containerView.removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: containerView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        if let area = trackingArea {
            containerView.addTrackingArea(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        autoDismissTimer?.invalidate()

        // Show dismiss button on hover
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            dismissButton.animator().alphaValue = 1.0
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        startAutoDismissTimer()

        // Hide dismiss button
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            dismissButton.animator().alphaValue = 0.6
        }
    }

    // MARK: - Public Interface

    func configure(appName: String) {
        // Could personalize based on app context in the future
    }

    func show(on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = targetScreen.visibleFrame

        // Position at bottom-center with padding
        let padding: CGFloat = 24
        let toastWidth: CGFloat = 300

        let finalX = screenFrame.midX - (toastWidth / 2)
        let finalY = screenFrame.minY + padding

        // Start position: below final position
        let startY = finalY - 30
        setFrameOrigin(NSPoint(x: finalX, y: startY))
        alphaValue = 0

        setupTrackingArea()
        orderFront(nil)

        // Animate in: slide up + fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(NSPoint(x: finalX, y: finalY))
            animator().alphaValue = 1.0
        }

        // Start video
        startVideoPlayback()
        startAutoDismissTimer()
    }

    func dismiss(animated: Bool = true) {
        autoDismissTimer?.invalidate()

        if animated {
            let currentOrigin = frame.origin

            // Animate out: fade only
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.stopVideoPlayback()
                self?.orderOut(nil)
                self?.onDismiss?()
            })
        } else {
            stopVideoPlayback()
            orderOut(nil)
            onDismiss?()
        }
    }

    // MARK: - Timer Management

    private func startAutoDismissTimer() {
        autoDismissTimer?.invalidate()

        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissDelay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isHovered else { return }
            self.dismiss()
        }
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        dismiss()
    }

    @objc private func toastClicked() {
        onActivate?()
        dismiss(animated: false)
    }
}
