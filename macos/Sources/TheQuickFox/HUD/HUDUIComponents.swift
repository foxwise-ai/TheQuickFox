//
//  HUDUIComponents.swift
//  TheQuickFox
//
//  UI components for the HUD interface
//

import Cocoa
import Combine
import QuartzCore

/// Custom button for HUD tabs with a "grooved" appearance.
class HUDTabButton: NSButton {

    /// Shortcut hint label (e.g., "⇥" for Tab)

    private let theme = ThemeManager.shared
    private let shortcutLabel = NSTextField(labelWithString: "")

    private var cancellables = Set<AnyCancellable>()
    /// Whether the shortcut hint is currently visible
   var shortcutHintVisible: Bool = false {
        didSet {
            updateShortcutHintVisibility()
        }
    }

    /// The shortcut hint text to display (e.g., "⇥" or "1")
    var shortcutHint: String = "" {
        didSet {
            updateShortcutLabelText()
        }
    }

    private func updateShortcutLabelText() {
        // Use attributed string with negative baseline offset to push text down
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: theme.textTertiary,
            .baselineOffset: -2,
            .paragraphStyle: paragraphStyle
        ]
        shortcutLabel.attributedStringValue = NSAttributedString(string: shortcutHint, attributes: attributes)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.pushOnPushOff)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 4.0
        font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentTintColor = titleColor


        setupThemeBinding()
        setupShortcutLabel()
   }

    private func setupShortcutLabel() {
        // Use monospace digits for proper centering
        let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        shortcutLabel.font = monoFont
        shortcutLabel.textColor = theme.textTertiary
        shortcutLabel.backgroundColor = theme.buttonBackground
        shortcutLabel.wantsLayer = true
        shortcutLabel.layer?.cornerRadius = 3
        shortcutLabel.layer?.masksToBounds = true
        shortcutLabel.layer?.borderWidth = 0.5
        shortcutLabel.layer?.borderColor = theme.hudBorder.cgColor
        shortcutLabel.drawsBackground = true
        shortcutLabel.alignment = .center
        shortcutLabel.alphaValue = 0.0
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        // Use single-line cell for vertical centering
        shortcutLabel.usesSingleLineMode = true
        shortcutLabel.lineBreakMode = .byClipping
        if let cell = shortcutLabel.cell as? NSTextFieldCell {
            cell.isScrollable = false
            cell.wraps = false
        }

        addSubview(shortcutLabel)

        // Position at trailing edge, vertically centered
        NSLayoutConstraint.activate([
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.widthAnchor.constraint(equalToConstant: 18),
            shortcutLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    private func updateShortcutHintVisibility() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = shortcutHintVisible ? 0.15 : 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shortcutLabel.animator().alphaValue = shortcutHintVisible ? 1.0 : 0.0
        }
    }

    /// Right padding reserves space for shortcut badge (18px badge + 6px margin + 10px spacing from text)
    var padding: NSEdgeInsets {
        NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 34)
    }

    var titleColor: NSColor {

        theme.textSecondary
   }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += padding.left + padding.right
        size.height += padding.top + padding.bottom
        return size
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var state: NSControl.StateValue {
        didSet { updateAppearance() }
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    private func setupThemeBinding() {
        theme.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.contentTintColor = self?.titleColor
                self?.updateAppearance()
                self?.updateShortcutLabelTheme()
            }
            .store(in: &cancellables)
    }

    private func updateShortcutLabelTheme() {
        shortcutLabel.textColor = theme.textTertiary
        shortcutLabel.backgroundColor = theme.buttonBackground
        shortcutLabel.layer?.borderColor = theme.hudBorder.cgColor
        // Re-apply attributed string with updated color
        if !shortcutHint.isEmpty {
            updateShortcutLabelText()
        }
    }

    private func updateAppearance() {
        if isHighlighted {

            layer?.backgroundColor = theme.buttonBackgroundHover.cgColor
       } else if state == .on {

            layer?.backgroundColor = theme.buttonBackgroundSelected.cgColor
       } else {
            layer?.backgroundColor = .clear
        }
    }
}

// subclass HUDTabButton to adjust height of subtabs
//
class HUDSubTabButton: HUDTabButton {
    override var padding: NSEdgeInsets {
        NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 32)
    }

    override var titleColor: NSColor {

        ThemeManager.shared.textTertiary
   }
}
