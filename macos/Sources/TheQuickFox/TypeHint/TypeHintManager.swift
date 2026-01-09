//
//  TypeHintManager.swift
//  TheQuickFox
//
//  Manages the typing hint system lifecycle, coordinating between
//  TypingMonitor (detection) and TypeHintToast (UI display).
//

import Cocoa
import Combine

@MainActor
final class TypeHintManager {

    // MARK: - Singleton

    static let shared = TypeHintManager()

    // MARK: - Properties

    private var toast: TypeHintToast?
    private var cancellables = Set<AnyCancellable>()
    private let store = AppStore.shared

    /// Whether the hint system is enabled
    private(set) var isEnabled: Bool = true

    /// User preference key for hint system
    private let enabledKey = "com.foxwiseai.thequickfox.typeHintEnabled"

    // MARK: - Initialization

    private init() {
        loadPreferences()
        setupBindings()
        setupMonitor()
    }

    // MARK: - Public Interface

    /// Start the type hint system
    func start() {
        guard isEnabled else { return }
        TypingMonitor.shared.startMonitoring()
        LoggingManager.shared.info(.generic, "TypeHintManager started")
    }

    /// Stop the type hint system
    func stop() {
        TypingMonitor.shared.stopMonitoring()
        hideHint()
        LoggingManager.shared.info(.generic, "TypeHintManager stopped")
    }

    /// Enable or disable the hint system
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)

        if enabled {
            start()
        } else {
            stop()
        }

        LoggingManager.shared.info(.generic, "TypeHintManager enabled: \(enabled)")
    }

    /// Manually show a hint (for testing or manual triggers)
    func showHint(appName: String = "") {
        // Don't show if HUD is visible
        guard !store.hudState.isVisible else { return }

        // Dismiss existing toast
        toast?.dismiss(animated: false)

        // Create and configure new toast
        let newToast = TypeHintToast()
        newToast.configure(appName: appName)

        newToast.onDismiss = { [weak self] in
            self?.toast = nil
        }

        newToast.onActivate = { [weak self] in
            // User clicked the hint - trigger TQF activation
            self?.toast = nil
            // The double-control detector will handle actual activation
            // For now, just log that user was interested
            LoggingManager.shared.info(.generic, "TypeHint clicked - user interested in TQF")
        }

        newToast.show()
        toast = newToast

        LoggingManager.shared.info(.ui, "TypeHint shown for app: \(appName)")
    }

    /// Hide any visible hint
    func hideHint() {
        toast?.dismiss()
        toast = nil
    }

    /// Reset typing statistics (call when user activates TQF)
    func resetStats() {
        TypingMonitor.shared.resetStats()
    }

    // MARK: - Private Setup

    private func loadPreferences() {
        // Default to enabled if not set
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
    }

    private func setupBindings() {
        // Hide hint when HUD becomes visible
        store.hudStatePublisher
            .map(\.isVisible)
            .removeDuplicates()
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.hideHint()
                    self?.resetStats()
                }
            }
            .store(in: &cancellables)
    }

    private func setupMonitor() {
        TypingMonitor.shared.onShouldShowHint = { [weak self] appName in
            Task { @MainActor in
                self?.showHint(appName: appName)
            }
        }
    }
}
