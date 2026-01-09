//
//  ThemeManager.swift
//  TheQuickFox
//
//  Centralized theme management for light/dark mode support.
//  Observes system appearance changes and provides dynamic colors.
//

import Cocoa
import Combine

/// Centralized manager for theme/appearance detection and dynamic colors
public final class ThemeManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = ThemeManager()

    // MARK: - Published State

    /// Whether the system is currently in dark mode
    @Published public private(set) var isDarkMode: Bool = true

    // MARK: - Theme Colors

    /// Primary background color for HUD and panels
    public var hudBackground: NSColor {
        isDarkMode
            ? NSColor.black.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.92)
    }

    /// Border color for HUD and panels
    public var hudBorder: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.12)
    }

    /// Primary text color
    public var textPrimary: NSColor {
        isDarkMode ? .white : .black
    }

    /// Secondary text color (for hints, placeholders)
    public var textSecondary: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.5)
    }

    /// Tertiary text color (for very subtle hints)
    public var textTertiary: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.35)
            : NSColor.black.withAlphaComponent(0.35)
    }

    /// Placeholder text color
    public var textPlaceholder: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.3)
            : NSColor.black.withAlphaComponent(0.5)
    }

    /// Button background color (normal state)
    public var buttonBackground: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06)
    }

    /// Button background color (hover state)
    public var buttonBackgroundHover: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.12)
    }

    /// Button background color (selected state)
    public var buttonBackgroundSelected: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.1)
            : NSColor.black.withAlphaComponent(0.08)
    }

    /// Button text color (normal state)
    public var buttonText: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.5)
    }

    /// Button text color (hover state)
    public var buttonTextHover: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.8)
            : NSColor.black.withAlphaComponent(0.8)
    }

    /// Toast/notification background color
    public var toastBackground: NSColor {
        isDarkMode
            ? NSColor.black.withAlphaComponent(0.9)
            : NSColor.white.withAlphaComponent(0.95)
    }

    /// Loader/wave color
    public var loaderColor: NSColor {
        isDarkMode ? .white : NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
    }

    /// Caret/cursor color (uses system accent color which adapts automatically)
    public var caretColor: NSColor {
        NSColor.controlAccentColor
    }

    /// Accent color (uses system accent color)
    public var accentColor: NSColor {
        NSColor.controlAccentColor
    }

    /// Code inline background color
    public var codeInlineBackground: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06)
    }

    /// Code block background color
    public var codeBlockBackground: NSColor {
        isDarkMode
            ? NSColor.black.withAlphaComponent(0.3)
            : NSColor.black.withAlphaComponent(0.04)
    }

    /// Code block border color
    public var codeBlockBorder: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.15)
            : NSColor.black.withAlphaComponent(0.1)
    }

    /// Code text color
    public var codeText: NSColor {
        isDarkMode
            ? NSColor(calibratedRed: 0.53, green: 0.81, blue: 0.92, alpha: 1.0)  // #87CEEB
            : NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.73, alpha: 1.0)   // Darker blue for light mode
    }

    /// Link color
    public var linkColor: NSColor {
        isDarkMode
            ? NSColor(calibratedRed: 0.36, green: 0.68, blue: 0.89, alpha: 1.0)  // #5DADE2
            : NSColor.linkColor
    }

    /// Blockquote border color
    public var blockquoteBorder: NSColor {
        isDarkMode
            ? NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.89, alpha: 1.0)  // #4A90E2
            : NSColor.systemBlue
    }

    /// Blockquote background color
    public var blockquoteBackground: NSColor {
        isDarkMode
            ? NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.89, alpha: 0.1)
            : NSColor.systemBlue.withAlphaComponent(0.08)
    }

    /// Table border color
    public var tableBorder: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.15)
    }

    /// Table header background color
    public var tableHeaderBackground: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.1)
            : NSColor.black.withAlphaComponent(0.05)
    }

    /// Separator/divider color
    public var separator: NSColor {
        isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.12)
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?

    // MARK: - Initialization

    private init() {
        // Detect initial appearance
        updateAppearance()

        // Observe system appearance changes
        setupAppearanceObserver()
    }

    deinit {
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Private Methods

    private func updateAppearance() {
        if #available(macOS 10.14, *) {
            let appearance = NSApp.effectiveAppearance
            isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            // Pre-Mojave always light mode
            isDarkMode = false
        }
    }

    private func setupAppearanceObserver() {
        // Observe the distributed notification for appearance changes
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAppearance()
        }

        // Also observe the app's effective appearance directly
        if #available(macOS 10.14, *) {
            NSApp.publisher(for: \.effectiveAppearance)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateAppearance()
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - Public Methods

    /// Force a refresh of the current appearance state
    public func refresh() {
        updateAppearance()
    }

    /// Returns the appropriate color based on current theme
    public func color(light: NSColor, dark: NSColor) -> NSColor {
        isDarkMode ? dark : light
    }

    /// Returns a CSS hex color string
    public func hexString(for color: NSColor) -> String {
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Returns a CSS rgba color string
    public func rgbaString(for color: NSColor) -> String {
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return "rgba(0, 0, 0, 1)"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        let a = rgbColor.alphaComponent
        return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, a)
    }
}
