//
//  WindowHighlighter.swift
//  TheQuickFox
//
//  Provides visual feedback by highlighting the active window during OCR processing.
//  Shows a colored border around the target window to indicate which window is being
//  analyzed for context extraction.
//

import Cocoa
import CoreGraphics
import QuartzCore

/// Visual indicator that highlights the active window during processing
public final class WindowHighlighter {

    /// Shared singleton instance
    public static let shared = WindowHighlighter()

    /// The overlay window that draws the highlight border
    private var overlayWindow: NSWindow?
    private var trailWindows: [NSWindow] = []
    private var backdropWindow: NSWindow?
    private var workspaceObserver: NSObjectProtocol?
    private var trackedWindowID: CGWindowID?
    private var windowTrackingTimer: Timer?
    private var originalAppBundleID: String?

    /// Keep Metal animator alive during animation
    private var activeAnimator: MorphAnimator?

    /// Color for the highlight border
    private let highlightColor = NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.8)  // Bright magenta

    /// Border width in points
    private let borderWidth: CGFloat = 4.0

    /// Animation duration for fade in/out
    private let animationDuration: TimeInterval = 3.5

    private init() {
        setupWorkspaceObserver()
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        windowTrackingTimer?.invalidate()
    }

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
    }

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let activatedBundleID = app.bundleIdentifier

        // If switching back to the original app, show the backdrop
        if activatedBundleID == originalAppBundleID {
            showBackdropIfNeeded()
        } else {
            // Switching away, hide the backdrop
            hideBackdropIfNeeded()
        }
    }

    private func showBackdropIfNeeded() {
        guard let backdrop = backdropWindow, !backdrop.isVisible else { return }

        backdrop.alphaValue = 0.0
        backdrop.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            backdrop.animator().alphaValue = 1.0
        })
    }

    private func hideBackdropIfNeeded() {
        guard let backdrop = backdropWindow, backdrop.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            backdrop.animator().alphaValue = 0.0
        }) {
            backdrop.orderOut(nil)
        }
    }

    private func startTrackingWindow(_ windowID: CGWindowID) {
        trackedWindowID = windowID
        windowTrackingTimer?.invalidate()
        windowTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkWindowPosition()
        }
    }

    private func stopTrackingWindow() {
        windowTrackingTimer?.invalidate()
        windowTrackingTimer = nil
        trackedWindowID = nil
    }

    private func checkWindowPosition() {
        guard let windowID = trackedWindowID,
              let backdrop = backdropWindow,
              backdrop.isVisible else {
            stopTrackingWindow()
            return
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        guard let windowInfo = windowList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat else {
            hideBackdropIfNeeded()
            stopTrackingWindow()
            return
        }

        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let newCocoaY = screenFrame.height - y - backdrop.frame.height
        let newOrigin = NSPoint(x: x, y: newCocoaY)

        if backdrop.frame.origin != newOrigin {
            backdrop.setFrameOrigin(newOrigin)
        }
    }

    /// Shows a highlight border around the specified window
    /// - Parameters:
    ///   - windowInfo: Core Graphics window dictionary containing bounds and other info
    ///   - duration: How long to show the highlight (0 means indefinite)
    public func highlight(windowInfo: [String: Any], duration: TimeInterval = 0) {
        guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
            let x = boundsDict["X"] as? CGFloat,
            let y = boundsDict["Y"] as? CGFloat,
            let width = boundsDict["Width"] as? CGFloat,
            let height = boundsDict["Height"] as? CGFloat
        else {
            LoggingManager.shared.error(
                .generic, "WindowHighlighter: Invalid window bounds in windowInfo")
            return
        }

        let windowFrame = CGRect(x: x, y: y, width: width, height: height)
        let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID
        let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t

        // Get bundle ID from PID
        if let pid = ownerPID {
            originalAppBundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }

        showHighlight(around: windowFrame, windowID: windowID, duration: duration)
    }

    /// Shows a highlight border around the specified frame
    /// - Parameters:
    ///   - frame: The window frame to highlight
    ///   - windowID: The CGWindowID to track for position changes
    ///   - duration: How long to show the highlight (0 means indefinite)
    public func showHighlight(around frame: CGRect, windowID: CGWindowID?, duration: TimeInterval = 0) {
        // Run synchronously to ensure overlay window exists before animation is triggered
        // (the caller is already on main thread from the event handler)
        cleanupPreviousHighlight()

        createBackdropWindow(around: frame)
        createOverlayWindow(around: frame)
        animateIn()

        if let windowID = windowID {
            startTrackingWindow(windowID)
        }

        if duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.hideHighlight()
            }
        }
    }

    /// Cleans up previous highlight state without animation
    private func cleanupPreviousHighlight() {
        // Stop tracking
        stopTrackingWindow()

        // Cancel any active animation
        activeAnimator = nil

        // Remove all trail/ghost windows immediately
        for trailWindow in trailWindows {
            trailWindow.orderOut(nil)
        }
        trailWindows.removeAll()

        // Note: We don't clean up overlayWindow or backdropWindow here
        // because createOverlayWindow() and createBackdropWindow() handle that
    }

    /// Hides the current highlight
    public func hideHighlight() {
        DispatchQueue.main.async {
            self.animateOut()
        }
    }

    /// Immediately hides all highlighting without animation
    public func forceHideHighlight() {
        DispatchQueue.main.async {
            // Stop tracking
            self.stopTrackingWindow()
            self.originalAppBundleID = nil

            // Cancel any active animation
            self.activeAnimator = nil

            // Immediately hide and clean up overlay window
            self.overlayWindow?.orderOut(nil)
            self.overlayWindow = nil

            // Immediately hide and clean up all trail windows
            for trailWindow in self.trailWindows {
                trailWindow.orderOut(nil)
            }
            self.trailWindows.removeAll()

            // Immediately hide and clean up backdrop window
            self.backdropWindow?.orderOut(nil)
            self.backdropWindow = nil
        }
    }

    /// Animates the current highlight border to the HUD window bounds
    /// - Parameters:
    ///   - hudBounds: The target HUD window bounds to animate to
    ///   - duration: Animation duration (default: 1.2)
    ///   - completion: Called when animation completes
    public func animateToHUD(
        hudBounds: NSRect, duration: TimeInterval = 2.0, completion: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            guard let window = self.overlayWindow else {
                print("⚠️ animateToHUD: No overlay window, calling completion")
                completion()
                return
            }

            print("🎬 animateToHUD: Animating from: \(window.frame) to: \(hudBounds)")
            print("   Current activeAnimator: \(self.activeAnimator != nil ? "EXISTS" : "nil")")

            // Clean up any previous trail windows before creating new ones
            for trailWindow in self.trailWindows {
                trailWindow.orderOut(nil)
            }
            self.trailWindows.removeAll()

            // Cancel any existing animator
            self.activeAnimator = nil

            let startFrame = window.frame
            self.createOriginalWindowGhost(at: startFrame)

            guard let animator = MorphAnimator() else {
                print("⚠️ MorphAnimator failed to initialize, using fallback")
                self.fallbackAnimateToHUD(window: window, hudBounds: hudBounds, duration: duration, completion: completion)
                return
            }

            print("✅ Created new MorphAnimator, storing as activeAnimator")
            // Keep animator alive during animation
            self.activeAnimator = animator

            // if let borderView = window.contentView as? HighlightBorderView {
            //     borderView.enableGradientTrail()
            // }

            animator.animate(
                window: window,
                from: startFrame,
                to: hudBounds,
                duration: duration,
                onUpdate: { [weak self] progress in
                    if let borderView = window.contentView as? HighlightBorderView {
                        // borderView.updateMorphProgress(Float(progress))
                    }
                },
                completion: { [weak self] in
                    print("🏁 Metal animation completed")

                    if let borderView = window.contentView as? HighlightBorderView {
                        borderView.disableGradientTrail()
                        borderView.startTrailingEffect()
                    }

                    window.orderOut(nil)
                    self?.overlayWindow = nil

                    print("🗑️ Releasing activeAnimator")
                    self?.activeAnimator = nil  // Release animator

                    completion()
                }
            )
        }
    }

    private func fallbackAnimateToHUD(
        window: NSWindow,
        hudBounds: NSRect,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        let trailLayer = CAReplicatorLayer()
        trailLayer.frame = window.contentView!.layer!.bounds
        trailLayer.instanceCount = 60
        trailLayer.instanceDelay = 0.08
        trailLayer.instanceAlphaOffset = -0.016
        trailLayer.preservesDepth = false

        let translation = CATransform3DMakeTranslation(-12, -12, 0)
        trailLayer.instanceTransform = translation

        if let borderView = window.contentView as? HighlightBorderView {
            window.contentView?.layer?.insertSublayer(trailLayer, at: 0)
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            window.animator().setFrame(hudBounds, display: true)

            if let borderView = window.contentView as? HighlightBorderView {
                borderView.animator().frame = NSRect(origin: .zero, size: hudBounds.size)
            }
        }) {
            print("Fallback animation completed")

            if let borderView = window.contentView as? HighlightBorderView {
                borderView.disableGradientTrail()
                borderView.startTrailingEffect()
            }

            window.orderOut(nil)
            self.overlayWindow = nil

            completion()
        }
    }

    /// Creates a persistent ghost at the original window position that fades slowly
    private func createOriginalWindowGhost(at frame: NSRect) {
        // Create ghost window at original position
        let ghostWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        ghostWindow.level = .floating
        ghostWindow.isOpaque = false
        ghostWindow.backgroundColor = .clear
        ghostWindow.ignoresMouseEvents = true
        ghostWindow.hasShadow = false

        // Create ghost border view - start with good visibility
        let ghostBorderView = HighlightBorderView(
            frame: NSRect(origin: .zero, size: frame.size),
            borderWidth: 4.0,
            borderColor: highlightColor
        )
        ghostBorderView.alphaValue = 0.7  // Start quite visible

        ghostWindow.contentView = ghostBorderView
        ghostWindow.orderFront(nil)
        trailWindows.append(ghostWindow)

        // Slow fade out - user can see original window location for several seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Start fade after half second
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 4.0  // Very slow 4-second fade
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
                ghostWindow.animator().alphaValue = 0.0
            }) {
                ghostWindow.orderOut(nil)
                // Remove from array when fade completes
                if let windowIndex = self.trailWindows.firstIndex(of: ghostWindow) {
                    self.trailWindows.remove(at: windowIndex)
                }
            }
        }
    }

    /// Easing function for smooth animation
    private func easeInEaseOut(_ t: CGFloat) -> CGFloat {
        return t * t * (3.0 - 2.0 * t)
    }

    /// Creates a backdrop overlay that dims only the original window area
    private func createBackdropWindow(around targetFrame: CGRect) {
        backdropWindow?.orderOut(nil)
        backdropWindow = nil

        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let cocoaFrame = NSRect(
            x: targetFrame.origin.x,
            y: screenFrame.height - targetFrame.origin.y - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        let backdropWin = NSWindow(
            contentRect: cocoaFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backdropWin.level = .floating
        backdropWin.isOpaque = false
        backdropWin.backgroundColor = .clear
        backdropWin.ignoresMouseEvents = true
        backdropWin.hasShadow = false
        backdropWin.alphaValue = 0.0
        backdropWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let backdropView = NSView(frame: NSRect(origin: .zero, size: cocoaFrame.size))
        backdropView.wantsLayer = true
        backdropView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        backdropView.layer?.cornerRadius = 10.0
        backdropWin.contentView = backdropView

        backdropWindow = backdropWin
        backdropWin.orderFront(nil)
    }

    /// Creates the overlay window with a border around the target frame
    private func createOverlayWindow(around targetFrame: CGRect) {
        // Remove any existing overlay
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        // Convert from CG coordinates to Cocoa coordinates
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let cocoaFrame = NSRect(
            x: targetFrame.origin.x,
            y: screenFrame.height - targetFrame.origin.y - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        // Create the overlay window
        overlayWindow = NSWindow(
            contentRect: cocoaFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = overlayWindow else { return }

        // Configure window properties
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.alphaValue = 0.0

        // Create the border view
        let borderView = HighlightBorderView(
            frame: NSRect(origin: .zero, size: cocoaFrame.size),
            borderWidth: borderWidth,
            borderColor: highlightColor
        )

        window.contentView = borderView
        window.orderFront(nil)
    }

    /// Animates the highlight in with pulsing effect
    private func animateIn() {
        guard let window = overlayWindow else { return }

        // Fade in backdrop
        if let backdrop = backdropWindow {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                backdrop.animator().alphaValue = 1.0
            }
        }

        // Initial fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        } completionHandler: {
            // Start pulsing animation
            self.startPulsingAnimation()
        }
    }

    /// Creates a grotesque pulsing animation effect
    private func startPulsingAnimation() {
        guard let window = overlayWindow else { return }

        // Create a repeating pulse animation
        let pulseAnimation = {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // window.animator().alphaValue = 0.3
            }) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.4
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().alphaValue = 1.0
                }) {
                    // Continue pulsing if window still exists
                    if self.overlayWindow != nil {
                        self.startPulsingAnimation()
                    }
                }
            }
        }

        pulseAnimation()
    }

    /// Animates the highlight out and cleans up
    private func animateOut() {
        guard let window = overlayWindow else { return }

        // Start fading trails before hiding window
        if let borderView = window.contentView as? HighlightBorderView {
            borderView.fadeTrails()
        }

        // Clean up any remaining trail windows with gentle fade
        for trailWindow in trailWindows {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 2.0  // Slower fade for ghost
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
                trailWindow.animator().alphaValue = 0.0
            }) {
                trailWindow.orderOut(nil)
            }
        }
        trailWindows.removeAll()

        // Fade both the window and its border view (but keep backdrop)
        if let borderView = window.contentView as? HighlightBorderView {
            borderView.layer?.removeAllAnimations()
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.8
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0.0
            if let borderView = window.contentView {
                borderView.animator().alphaValue = 0.0
            }
        }) {
            window.orderOut(nil)
            self.overlayWindow = nil
        }
    }
}

/// Custom view that draws a smooth animated rainbow border with trailing effects
private final class HighlightBorderView: NSView {
    private let borderWidth: CGFloat
    private let borderColor: NSColor

    private var gradientLayer: CAGradientLayer!
    private var trailLayers: [CAGradientLayer] = []
    private var maskLayer: CAShapeLayer!
    private let cornerRadius: CGFloat = 10.0
    private var morphProgress: Float = 0.0

    init(frame frameRect: NSRect, borderWidth: CGFloat, borderColor: NSColor) {
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        super.init(frame: frameRect)
        self.wantsLayer = true
        setupAnimatedLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupAnimatedLayers() {
        guard let layer = self.layer else { return }

        // Main gradient layer with smooth animation
        gradientLayer = CAGradientLayer()
        gradientLayer.frame = bounds
        gradientLayer.type = .axial
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.colors = [
            CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.95),  // Magenta
            CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.95),  // Green
            CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.95),  // Yellow
            CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.95),  // Back to magenta
        ]
        gradientLayer.locations = [0.0, 0.33, 0.66, 1.0]

        // Create multiple trail layers for edge persistence
        for i in 0..<3 {
            let trailLayer = CAGradientLayer()
            trailLayer.frame = bounds
            trailLayer.type = .radial
            trailLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            trailLayer.endPoint = CGPoint(x: 1.2, y: 1.2)

            let alpha = 0.6 - (CGFloat(i) * 0.2)  // Decreasing alpha for each trail
            trailLayer.colors = [
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha),
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha * 0.5),
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
            ]
            trailLayer.locations = [0.0, 0.8, 1.0]
            trailLayer.compositingFilter = "overlayBlendMode"
            trailLayers.append(trailLayer)
        }

        // Create border mask
        maskLayer = CAShapeLayer()
        updateMask()

        // Set up layer hierarchy with trails
        gradientLayer.mask = maskLayer
        layer.addSublayer(gradientLayer)

        for (_, trailLayer) in trailLayers.enumerated() {
            // Create new mask layer for each trail (CAShapeLayer doesn't support copy)
            let trailMask = CAShapeLayer()
            trailMask.path = maskLayer.path
            trailMask.fillRule = maskLayer.fillRule
            trailLayer.mask = trailMask
            trailLayer.opacity = 0.0  // Start hidden
            layer.insertSublayer(trailLayer, below: gradientLayer)
        }

        startAnimation()
    }

    private func updateMask() {
        let outerRadius = cornerRadius
        let innerRadius = max(0, outerRadius - borderWidth)
        let borderRect = bounds
        let innerRect = NSRect(
            x: borderWidth,
            y: borderWidth,
            width: bounds.width - (borderWidth * 2),
            height: bounds.height - (borderWidth * 2)
        )

        let outerPath = NSBezierPath(
            roundedRect: borderRect, xRadius: outerRadius, yRadius: outerRadius)
        let innerPath = NSBezierPath(
            roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

        let combinedPath = NSBezierPath()
        combinedPath.append(outerPath)
        combinedPath.append(innerPath.reversed)

        if #available(macOS 14.0, *) {
            maskLayer.path = combinedPath.cgPath
            maskLayer.fillRule = .evenOdd
            // Update all trail masks too
            for trailLayer in trailLayers {
                if let trailMask = trailLayer.mask as? CAShapeLayer {
                    trailMask.path = combinedPath.cgPath
                    trailMask.fillRule = .evenOdd
                }
            }
        } else {
            // Fallback for macOS 13: create CGPath manually
            let cgPath = CGMutablePath()
            cgPath.addRoundedRect(in: borderRect, cornerWidth: outerRadius, cornerHeight: outerRadius)
            cgPath.addRoundedRect(in: innerRect, cornerWidth: innerRadius, cornerHeight: innerRadius)
            maskLayer.path = cgPath
            maskLayer.fillRule = .evenOdd
            // Update all trail masks too
            for trailLayer in trailLayers {
                if let trailMask = trailLayer.mask as? CAShapeLayer {
                    trailMask.path = cgPath
                    trailMask.fillRule = .evenOdd
                }
            }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer?.frame = bounds
        for trailLayer in trailLayers {
            trailLayer.frame = bounds
        }
        updateMask()
        CATransaction.commit()
    }

    private func startAnimation() {
        // Smooth gradient flow along the border perimeter
        let flowAnimation = CAKeyframeAnimation(keyPath: "endPoint")
        flowAnimation.values = [
            CGPoint(x: 1.0, y: 1.0),
            CGPoint(x: 0.0, y: 1.0),
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 1.0, y: 0.0),
            CGPoint(x: 1.0, y: 1.0)
        ]
        flowAnimation.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0]
        flowAnimation.duration = 4.0
        flowAnimation.repeatCount = .infinity
        flowAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Breathing effect - more noticeable on the original window
        let breatheAnimation = CAKeyframeAnimation(keyPath: "opacity")
        breatheAnimation.values = [0.9, 1.0, 0.9]
        breatheAnimation.keyTimes = [0.0, 0.5, 1.0]
        breatheAnimation.duration = 2.0
        breatheAnimation.repeatCount = .infinity
        breatheAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        gradientLayer.add(flowAnimation, forKey: "flow")
        gradientLayer.add(breatheAnimation, forKey: "breathe")

        // Ghostly trails that create persistence effect
        for (index, trailLayer) in trailLayers.enumerated() {
            let delay = Double(index) * 0.4
            let ghostAnimation = CAKeyframeAnimation(keyPath: "opacity")
            ghostAnimation.values = [0.0, 0.7, 0.5, 0.3, 0.15, 0.0]
            ghostAnimation.keyTimes = [0.0, 0.15, 0.3, 0.5, 0.8, 1.0]
            ghostAnimation.duration = 2.0 + delay
            ghostAnimation.beginTime = CACurrentMediaTime() + delay
            ghostAnimation.repeatCount = .infinity
            ghostAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)

            trailLayer.add(ghostAnimation, forKey: "ghost\(index)")
        }
    }

    func startTrailingEffect() {
        // Create persistent ghostly echoes when transitioning to HUD
        for (index, trailLayer) in trailLayers.enumerated() {
            // Remove existing animations for clean state
            trailLayer.removeAllAnimations()

            let delay = Double(index) * 0.2
            let persistAnimation = CAKeyframeAnimation(keyPath: "opacity")
            persistAnimation.values = [0.0, 0.6 - (CGFloat(index) * 0.15), 0.4 - (CGFloat(index) * 0.1), 0.2 - (CGFloat(index) * 0.05)]
            persistAnimation.keyTimes = [0.0, 0.2, 0.6, 1.0]
            persistAnimation.duration = 1.5 + delay
            persistAnimation.beginTime = CACurrentMediaTime() + delay
            persistAnimation.fillMode = .forwards
            persistAnimation.isRemovedOnCompletion = false
            persistAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)

            trailLayer.add(persistAnimation, forKey: "persistGhost")
        }
    }

    func fadeTrails() {
        // Gracefully fade the ghostly trails when HUD closes
        for (index, trailLayer) in trailLayers.enumerated() {
            let currentOpacity = trailLayer.presentation()?.opacity ?? trailLayer.opacity
            let delay = Double(index) * 0.1

            let fadeAnimation = CAKeyframeAnimation(keyPath: "opacity")
            fadeAnimation.values = [currentOpacity, currentOpacity * 0.7, 0.0]
            fadeAnimation.keyTimes = [0.0, 0.4, 1.0]
            fadeAnimation.duration = 2.0 + delay
            fadeAnimation.beginTime = CACurrentMediaTime() + delay
            fadeAnimation.fillMode = .forwards
            fadeAnimation.isRemovedOnCompletion = false
            fadeAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)

            trailLayer.add(fadeAnimation, forKey: "fadeGhost")
        }
    }

    func disableGradientTrail() {
        self.layer?.filters = nil
    }
}
