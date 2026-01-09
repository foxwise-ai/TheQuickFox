//
//  AnimatedCaretTextView.swift
//  TheQuickFox
//
//  NSTextView subclass that renders its own caret as a CALayer and animates its
//  movement for a subtle "flow" effect.
//

import Cocoa
import Combine
import QuartzCore
import AVFoundation

final class AnimatedCaretTextView: NSTextView {

    private let caretLayer = CALayer()
    private var lastCaretRect: CGRect = .zero
    private let placeholderLayer = CATextLayer()
    private var typingSoundPlayer: AVAudioPlayer?
    private let theme = ThemeManager.shared
    private var cancellables = Set<AnyCancellable>()

    /// Weak reference to the HUD view controller for keyboard shortcut handling
    weak var hudViewController: HUDViewController?

    /// Whether the loader is currently visible (to hide placeholder and caret)
    var isLoaderVisible: Bool = false {
        didSet {
            if isLoaderVisible != oldValue {
                updatePlaceholderVisibility()
                updateCaretVisibility()
            }
        }
    }

    /// Placeholder text shown when the text view is empty
    var placeholderString: String? {
        didSet {
            updatePlaceholderLayer()
        }
    }

    override var isFlipped: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Update caret position when we become first responder
            updateCaretPosition(animated: false)
        }
        return result
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        print("🪟 viewWillMove called, newWindow: \(newWindow != nil)")

        wantsLayer = true

        // Ensure layer uses flipped coordinate system (top-left origin)
        layer?.isGeometryFlipped = true

        // Setup placeholder layer (only if not already added)
        if placeholderLayer.superlayer == nil {
            layer?.addSublayer(placeholderLayer)
            placeholderLayer.isGeometryFlipped = true
            placeholderLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            placeholderLayer.foregroundColor = theme.textPlaceholder.cgColor
            placeholderLayer.fontSize = 18
            placeholderLayer.font = NSFont.systemFont(ofSize: 18, weight: .regular)
            placeholderLayer.opacity = 0.0  // Start hidden
            print("📝 Placeholder layer added")
        }

        // Setup caret layer (only if not already added)
        if caretLayer.superlayer == nil {
            layer?.addSublayer(caretLayer)
            caretLayer.backgroundColor = theme.caretColor.cgColor
            caretLayer.cornerRadius = 0.5
            caretLayer.opacity = 0.8
            print("✏️ Caret layer added with width will be 8")
        }

        // Setup theme binding and apply initial theme
        setupThemeBinding()
        applyTheme()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // When view moves to window, ensure placeholder is properly shown
        if window != nil {
            // Defer to next run loop to ensure layer is fully set up
            DispatchQueue.main.async { [weak self] in
                self?.applyTheme()
                self?.updatePlaceholderLayer()
            }
        }
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
        placeholderLayer.foregroundColor = theme.textPlaceholder.cgColor
        caretLayer.backgroundColor = theme.caretColor.cgColor
        // Force redraw
        placeholderLayer.setNeedsDisplay()
        caretLayer.setNeedsDisplay()
    }

    override func layout() {
        super.layout()
        updatePlaceholderLayer()
    }

    private func updatePlaceholderLayer() {
        guard let placeholder = placeholderString else {
            placeholderLayer.string = nil
            return
        }

        placeholderLayer.string = placeholder
        placeholderLayer.frame = NSRect(
            x: textContainerInset.width,
            y: textContainerInset.height,
            width: bounds.width - textContainerInset.width * 2,
            height: bounds.height - textContainerInset.height * 2
        )

        // Ensure visibility is correct
        updatePlaceholderVisibility()
    }

    override func didChangeText() {
        super.didChangeText()
        // Animate placeholder visibility based on text content
        updatePlaceholderVisibility()
    }

    /// Animates the placeholder alpha based on text content and loader state
    private func updatePlaceholderVisibility() {
        // Ensure layer is set up
        guard placeholderLayer.superlayer != nil else { return }

        let shouldShow = string.isEmpty && !isLoaderVisible && placeholderString != nil
        let targetOpacity: Float = shouldShow ? 1.0 : 0.0

        // Skip if no change needed
        guard abs(placeholderLayer.opacity - targetOpacity) > 0.01 else { return }

        let duration: TimeInterval = shouldShow ? 0.2 : 1.5  // Faster fade-in, slower fade-out

        // Animate the placeholder layer opacity
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = placeholderLayer.opacity
        animation.toValue = targetOpacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        placeholderLayer.add(animation, forKey: "opacity")
        placeholderLayer.opacity = targetOpacity

        CATransaction.commit()
    }

    /// Updates caret visibility based on loader state
    private func updateCaretVisibility() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        // Hide caret when loader is visible, show it otherwise
        caretLayer.opacity = isLoaderVisible ? 0.0 : 0.8

        CATransaction.commit()
    }

    /// NSTextView tells us where to draw the insertion point.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Don't call super - this prevents the system caret from drawing
        // We draw our own custom caret layer instead
        lastCaretRect = rect.integral
        updateCaretPosition(animated: true)
        print("🎯 drawInsertionPoint called: \(rect), layer opacity: \(caretLayer.opacity), superlayer: \(caretLayer.superlayer != nil)")
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        guard window != nil else { return }
        // When selection changes, animate caret to new position.
        updateCaretPosition(animated: true)
    }

    private func updateCaretPosition(animated: Bool) {
        // Get the insertion point rect from the layout manager
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let selectedRange = self.selectedRange()

        // Calculate insertion point rect
        var caretRect = NSRect.zero
        if selectedRange.length == 0 {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedRange.location)
            caretRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 0), in: textContainer)
            caretRect.origin.x += textContainerOrigin.x
            caretRect.origin.y += textContainerOrigin.y

            // Use font line height if rect height is 0
            if caretRect.height == 0 {
                let lineHeight = layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 18))
                caretRect.size.height = lineHeight
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let flippedY = caretRect.origin.y

        caretLayer.frame = CGRect(
            x: caretRect.origin.x,
            y: flippedY,
            width: 3,
            height: caretRect.height)
        print("📍 updateCaretPosition: frame=\(caretLayer.frame), opacity=\(caretLayer.opacity)")
        CATransaction.commit()

        guard animated else { return }

        let anim = CABasicAnimation(keyPath: "position")
        anim.duration = 0.15
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fromValue = caretLayer.presentation()?.position
        anim.toValue = caretLayer.position
        caretLayer.add(anim, forKey: "position")
    }

    private func playTypingSound() {
        guard let soundURL = Bundle.main.url(forResource: "press", withExtension: "wav") else {
            print("Could not find press.wav in bundle")
            return
        }

        do {
            typingSoundPlayer = try AVAudioPlayer(contentsOf: soundURL)
            typingSoundPlayer?.volume = 0.3
            typingSoundPlayer?.play()
        } catch {
            print("Failed to play typing sound: \(error)")
        }
    }

    /// Helper to find HUDViewController via direct reference or responder chain
    private func findHUDViewController() -> HUDViewController? {
        // Use the direct weak reference if available
        if let vc = hudViewController {
            return vc
        }
        // Fallback: walk the responder chain
        var responder: NSResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? HUDViewController {
                return viewController
            }
            responder = currentResponder.nextResponder
        }
        return nil
    }

    /// Detect ⌘↩ (Cmd+Enter), arrow keys, Tab, and 1/2/3 for shortcuts.
    override func keyDown(with event: NSEvent) {
        // Return / Enter key codes: 36 (Return) or 76 (Enter on num-pad)
        if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command) {
            if let viewController = findHUDViewController() {
                viewController.submitCurrentQuery()
                return
            }
        }

        // Arrow key codes: Up=126, Down=125
        if event.keyCode == 126 { // Up arrow
            if let viewController = findHUDViewController() {
                viewController.navigateHistoryUp()
                return
            }
        }

        if event.keyCode == 125 { // Down arrow
            if let viewController = findHUDViewController() {
                viewController.navigateHistoryDown()
                return
            }
        }

        // Tab key (keyCode 48) - switch between Ask and Compose/Code modes
        if event.keyCode == 48 && !event.modifierFlags.contains(.shift) {
            print("🎹 Tab key pressed, checking shortcut window...")
            if let viewController = findHUDViewController() {
                print("🎹 Found HUDViewController, shortcutsActive: \(viewController.shortcutsActive)")
                if viewController.handleTabKeyIfInShortcutWindow() {
                    print("🎹 Tab shortcut handled!")
                    return
                }
            } else {
                print("🎹 Could not find HUDViewController!")
            }
        }

        // Number keys 1/2/3 (keyCodes 18/19/20) - switch tones in Compose mode
        if event.keyCode >= 18 && event.keyCode <= 20 {
            print("🎹 Number key \(event.keyCode - 17) pressed, checking shortcut window...")
            if let viewController = findHUDViewController() {
                print("🎹 Found HUDViewController, shortcutsActive: \(viewController.shortcutsActive)")
                if viewController.handleToneShortcutIfInShortcutWindow(keyCode: event.keyCode) {
                    print("🎹 Tone shortcut handled!")
                    return
                }
            } else {
                print("🎹 Could not find HUDViewController!")
            }
        }

        // Play typing sound for regular character keys
        if event.charactersIgnoringModifiers?.rangeOfCharacter(from: .alphanumerics) != nil ||
           event.charactersIgnoringModifiers?.rangeOfCharacter(from: .punctuationCharacters) != nil ||
           event.charactersIgnoringModifiers?.rangeOfCharacter(from: .symbols) != nil {
            playTypingSound()
        }

        super.keyDown(with: event)
    }
}
