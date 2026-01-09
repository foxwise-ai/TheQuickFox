//
//  InsertionFailureToast.swift
//  TheQuickFox
//
//  Toast notification that appears when text insertion fails
//

import Cocoa
import Combine

final class InsertionFailureToast: NSPanel {

    // MARK: - UI Components

    private let containerView = NSView()
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let responsePreviewLabel = NSTextField(labelWithString: "")
    private let countdownIndicator = RadialCountdownView()
    private let copyButton = NSButton()
    private let closeButton = NSButton()
    private let historyHintLabel = NSTextField(labelWithString: "")
    private let historyButton = NSButton()

    // MARK: - Theme

    private let theme = ThemeManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Properties

    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    private var countdownTimer: Timer?
    private var countdownStartTime: Date?
    private let countdownDuration: TimeInterval = 20.0
    private var showHistoryHint: Bool = false
    private var historyButtonTrackingArea: NSTrackingArea?

    private let defaultHeight: CGFloat = 140
    private let expandedHeight: CGFloat = 170

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
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
        containerView.layer?.backgroundColor = theme.toastBackground.cgColor
        containerView.layer?.borderColor = theme.hudBorder.cgColor

        titleLabel.textColor = theme.textPrimary
        errorLabel.textColor = theme.textSecondary
        responsePreviewLabel.textColor = theme.textSecondary

        copyButton.layer?.backgroundColor = theme.buttonBackground.cgColor
        copyButton.contentTintColor = theme.textPrimary

        closeButton.contentTintColor = theme.textSecondary

        historyHintLabel.textColor = theme.textSecondary
        historyButton.contentTintColor = theme.textSecondary
    }

    // MARK: - Setup

    private func setupUI() {
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = theme.toastBackground.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = theme.hudBorder.cgColor

        // App icon
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 8
        iconImageView.layer?.masksToBounds = true

        // Title label
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = theme.textPrimary
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingTail

        // Error label
        errorLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        errorLabel.textColor = theme.textSecondary
        errorLabel.isBordered = false
        errorLabel.isEditable = false
        errorLabel.drawsBackground = false
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 1

        // Response preview label
        responsePreviewLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        responsePreviewLabel.textColor = theme.textSecondary
        responsePreviewLabel.isBordered = false
        responsePreviewLabel.isEditable = false
        responsePreviewLabel.drawsBackground = false
        responsePreviewLabel.lineBreakMode = .byTruncatingTail
        responsePreviewLabel.maximumNumberOfLines = 1
        responsePreviewLabel.cell?.wraps = false
        responsePreviewLabel.cell?.truncatesLastVisibleLine = true

        // Copy button
        copyButton.title = "Copy"
        copyButton.bezelStyle = .rounded
        copyButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyButton.target = self
        copyButton.action = #selector(copyButtonTapped)
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = theme.buttonBackground.cgColor
        copyButton.layer?.cornerRadius = 6
        copyButton.isBordered = false
        copyButton.contentTintColor = theme.textPrimary

        // Close button
        closeButton.title = ""
        closeButton.bezelStyle = .roundRect
        closeButton.isBordered = false
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(config)
        closeButton.contentTintColor = theme.textSecondary
        closeButton.target = self
        closeButton.action = #selector(closeButtonTapped)

        // History hint label
        historyHintLabel.stringValue = "View Previous Responses in"
        historyHintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        historyHintLabel.textColor = theme.textSecondary
        historyHintLabel.isBordered = false
        historyHintLabel.isEditable = false
        historyHintLabel.drawsBackground = false
        historyHintLabel.isHidden = true

        // History button
        historyButton.title = "History"
        historyButton.bezelStyle = .inline  // Minimal padding
        historyButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        historyButton.target = self
        historyButton.action = #selector(historyButtonTapped)
        historyButton.wantsLayer = true
        historyButton.layer?.backgroundColor = NSColor.clear.cgColor  // No background by default
        historyButton.layer?.cornerRadius = 6
        historyButton.isBordered = false
        historyButton.contentTintColor = theme.textSecondary
        historyButton.isHidden = true

        // Layout
        [iconImageView, titleLabel, errorLabel, responsePreviewLabel, countdownIndicator, copyButton, closeButton, historyHintLabel, historyButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview($0)
        }

        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(containerView)

        NSLayoutConstraint.activate([
            // Container fills the panel
            containerView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),

            // App icon (top-left)
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            // Title label (next to icon)
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            // Error label (below title)
            errorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            errorLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // Response preview (below error label)
            responsePreviewLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 8),
            responsePreviewLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            responsePreviewLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // Copy button (bottom-right)
            copyButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            copyButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            copyButton.widthAnchor.constraint(equalToConstant: 70),
            copyButton.heightAnchor.constraint(equalToConstant: 28),

            // Countdown indicator (left of close button)
            countdownIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            countdownIndicator.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            countdownIndicator.widthAnchor.constraint(equalToConstant: 16),
            countdownIndicator.heightAnchor.constraint(equalToConstant: 16),

            // Close button (top-right)
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            // History hint label (bottom, left of button)
            historyHintLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14),
            historyHintLabel.trailingAnchor.constraint(equalTo: historyButton.leadingAnchor, constant: 0),

            // History button (bottom, right of label)
            historyButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -9),
            historyButton.heightAnchor.constraint(equalToConstant: 24),
            historyButton.widthAnchor.constraint(equalToConstant: 50),  // Reduced from 80

            // Center the label+button group
            historyButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor, constant: 48),  // Adjusted centering
        ])
    }

    // MARK: - Public Interface

    func configure(appIcon: NSImage?, appName: String, errorMessage: String, errorDetail: String, responseText: String, showHistoryHint: Bool = false) {
        self.showHistoryHint = showHistoryHint
        if let icon = appIcon {
            iconImageView.image = icon
        } else {
            // Fallback to generic app icon
            iconImageView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: "App")?
                .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
        }

        titleLabel.stringValue = "Failed to insert text"
        if !appName.isEmpty {
            titleLabel.stringValue += " in \(appName)"
        }

        errorLabel.stringValue = errorDetail

        // Show preview of response (first ~57 chars, single line)
        let previewLength = 57
        let cleanedText = responseText.replacingOccurrences(of: "\n", with: " ")
        if cleanedText.count > previewLength {
            let preview = cleanedText.prefix(previewLength)
            responsePreviewLabel.stringValue = String(preview) + "..."
        } else {
            responsePreviewLabel.stringValue = cleanedText
        }

        // Show/hide history hint (label + button) and adjust height
        historyHintLabel.isHidden = !showHistoryHint
        historyButton.isHidden = !showHistoryHint

        // Setup tracking area for hover effect when button becomes visible
        if showHistoryHint {
            setupHistoryButtonTracking()
        }

        // Update window height based on hint visibility
        let currentFrame = frame
        let newHeight = showHistoryHint ? expandedHeight : defaultHeight
        setFrame(NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: currentFrame.width, height: newHeight), display: false)
    }

    private func setupHistoryButtonTracking() {
        // Remove old tracking area if exists
        if let oldArea = historyButtonTrackingArea {
            historyButton.removeTrackingArea(oldArea)
        }

        // Create new tracking area
        let trackingArea = NSTrackingArea(
            rect: historyButton.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        historyButton.addTrackingArea(trackingArea)
        historyButtonTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        // Check if mouse entered the history button
        let locationInButton = historyButton.convert(event.locationInWindow, from: nil)
        if historyButton.bounds.contains(locationInButton) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                historyButton.animator().contentTintColor = theme.textPrimary
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Restore original color when mouse exits
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            historyButton.animator().contentTintColor = theme.textSecondary
        }
    }

    @objc private func historyButtonTapped() {
        onOpenHistory?()
    }

    func show(at screen: NSScreen? = nil, from hudFrame: NSRect? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = targetScreen.visibleFrame

        // Position at bottom-right corner with padding
        let padding: CGFloat = 20
        let toastWidth: CGFloat = 420  // Match init width
        let toastHeight = showHistoryHint ? expandedHeight : defaultHeight
        let finalX = screenFrame.maxX - toastWidth - padding
        let finalY = screenFrame.minY + padding

        // Determine start position
        let startPosition: NSPoint
        if let hudFrame = hudFrame {
            // Start from HUD position (center of HUD)
            let startX = hudFrame.midX - (toastWidth / 2)
            let startY = hudFrame.midY - (toastHeight / 2)
            startPosition = NSPoint(x: startX, y: startY)
            print("🎬 Toast animating from HUD center (\(startX), \(startY)) to final position (\(finalX), \(finalY))")
            print("   HUD frame: \(hudFrame), Toast size: \(toastWidth)x\(toastHeight)")
        } else {
            // Fallback: start off-screen to the right
            startPosition = NSPoint(x: screenFrame.maxX + toastWidth, y: finalY)
            print("⚠️ No HUD frame provided, using fallback animation")
        }

        // Set initial position and alpha
        setFrameOrigin(startPosition)
        alphaValue = 0.5  // Start semi-transparent so it's visible during animation
        orderFront(nil)

        // Small delay to ensure initial position is committed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // Animate to final position with fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.animator().setFrameOrigin(NSPoint(x: finalX, y: finalY))
                self.animator().alphaValue = 1.0
            }
        }

        // Start countdown
        startCountdown()
    }

    private func startCountdown() {
        countdownStartTime = Date()

        // Update countdown indicator every 0.1 seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, let startTime = self.countdownStartTime else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, self.countdownDuration - elapsed)
            let progress = remaining / self.countdownDuration

            // Update radial indicator (starts at 1.0, goes to 0.0)
            self.countdownIndicator.progress = progress

            // Auto-dismiss when countdown reaches 0
            if remaining <= 0 {
                timer.invalidate()
                self.onClose?()
            }
        }
    }

    func dismiss() {
        // Stop countdown timer
        countdownTimer?.invalidate()
        countdownTimer = nil

        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens[0].visibleFrame
        let toastWidth: CGFloat = 420  // Match init width

        // Animate sliding out to the right (pure UI method, no state changes)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrameOrigin(NSPoint(x: screenFrame.maxX + toastWidth, y: frame.origin.y))
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    // MARK: - Actions

    @objc private func copyButtonTapped() {
        onCopy?()

        // Visual feedback: green checkmark briefly
        copyButton.title = "✓ Copied"
        copyButton.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy"
            self?.copyButton.contentTintColor = self?.theme.textPrimary
        }
    }

    @objc private func closeButtonTapped() {
        onClose?()  // Trigger state change, which will call dismiss() via ToastManager
    }
}

// MARK: - Radial Countdown View

final class RadialCountdownView: NSView {

    private let theme = ThemeManager.shared

    var progress: Double = 1.0 {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2

        // Draw background circle (empty state)
        let bgColor = theme.isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.15)
        context.setFillColor(bgColor.cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.fillPath()

        // Draw progress arc (starts full, goes to empty)
        if progress > 0 {
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)

            // Start at top (12 o'clock = -π/2) and go clockwise
            let startAngle = -CGFloat.pi / 2
            let endAngle = startAngle + (CGFloat.pi * 2 * progress)

            context.move(to: center)
            context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            context.closePath()
            context.fillPath()
        }
    }
}
