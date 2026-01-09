//
//  UserPreferences.swift
//  TheQuickFox
//
//  Persists user preferences across app sessions using UserDefaults
//

import Foundation

/// Manages persistent user preferences for mode and tone settings
final class UserPreferences {

    // MARK: - Singleton

    static let shared = UserPreferences()

    // MARK: - Keys

    private enum Keys {
        static let lastMode = "com.foxwiseai.thequickfox.lastMode"
        static let lastTone = "com.foxwiseai.thequickfox.lastTone"
    }

    // MARK: - Properties

    private let defaults = UserDefaults.standard

    // MARK: - Initialization

    private init() {}

    // MARK: - Mode Persistence

    /// The last user-selected mode. Returns nil if never set.
    var lastMode: HUDMode? {
        get {
            guard let rawValue = defaults.string(forKey: Keys.lastMode) else {
                return nil
            }
            return HUDMode(rawValue: rawValue)
        }
        set {
            defaults.set(newValue?.rawValue, forKey: Keys.lastMode)
        }
    }

    /// Returns the preferred mode based on saved preference and app context.
    /// - Parameter isDevelopmentApp: Whether the current frontmost app is a development app
    /// - Returns: The appropriate mode to use
    func preferredMode(isDevelopmentApp: Bool) -> HUDMode {
        // If user has explicitly set a mode, respect it
        if let savedMode = lastMode {
            // Only exception: Code mode in non-dev apps falls back to Compose
            if savedMode == .code && !isDevelopmentApp {
                return .compose
            }
            return savedMode
        }

        // No saved preference (new user) - auto-detect based on app type
        return isDevelopmentApp ? .code : .compose
    }

    // MARK: - Tone Persistence

    /// The last user-selected tone for Compose mode. Returns .formal if never set.
    var lastTone: ResponseTone {
        get {
            guard let rawValue = defaults.string(forKey: Keys.lastTone) else {
                return .formal
            }
            return ResponseTone(rawValue: rawValue) ?? .formal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.lastTone)
        }
    }

    // MARK: - Convenience Methods

    /// Saves the current mode preference
    func saveMode(_ mode: HUDMode) {
        lastMode = mode
    }

    /// Saves the current tone preference
    func saveTone(_ tone: ResponseTone) {
        lastTone = tone
    }
}
