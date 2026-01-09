//
//  HUDManager.swift
//  TheQuickFox
//
//  HUD manager using clean architecture
//

import Cocoa
import Combine

/// HUD manager that coordinates between the AppStore and UI
@MainActor
final class HUDManager: ObservableObject {

    // MARK: - Singleton

    static let shared: HUDManager = {
        MainActor.assumeIsolated {
            HUDManager()
        }
    }()

    // MARK: - Dependencies

    private let store = AppStore.shared
    private let hudViewController = HUDViewController()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // Load the view controller to ensure UI is ready
        _ = hudViewController.view
        setupBindings()
    }

    // MARK: - Public Interface

    func presentHUD(initialMode: HUDMode = .compose, demoPageContext: String? = nil) {
        // Check if we can restore an existing session
        if store.sessionState.canRestore && demoPageContext == nil {
            // Resume existing session - restore session state and show immediately without animation
            store.dispatch(.session(.restore))
            store.dispatch(.hud(.showWindow))
        } else {
            // Get saved tone preference (defaults to .formal if never set)
            let savedTone = UserPreferences.shared.lastTone

            // Start new session with animation
            store.dispatch(.session(.start(
                mode: initialMode,
                tone: savedTone,
                screenshot: nil,  // Screenshot will be updated separately
                demoPageContext: demoPageContext
            )))
            store.dispatch(.hud(.prepareWindow))
        }
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

    // MARK: - Window Service Interface

    func showHUD(skipScreenshot: Bool = false) {
        if skipScreenshot {
            store.dispatch(.hud(.showWindow))
        } else {
            // This will be handled by the caller with presentHUD(with:)
            store.dispatch(.hud(.showWindow))
        }
    }

    func setHUDVisible(_ visible: Bool) {
        if visible {
            store.dispatch(.hud(.showWindow))
        } else {
            store.dispatch(.hud(.hide))
        }
    }

    // MARK: - Direct UI Interface (for effects handler)

    func showUI() {
        // Direct UI call - no action dispatch to avoid loops
        if !store.hudState.isVisible {
            hudViewController.presentHUD()
        }
    }

    func hideUI() {
        // Direct UI call - no action dispatch
        hudViewController.hideHUD()
    }
    
    func getCurrentWindowFrame() -> NSRect? {
        return hudViewController.getWindowFrame()
    }
    
    func setWindowFrame(_ frame: NSRect) {
        hudViewController.setWindowFrame(frame)
    }
    
    func setPreserveWindowPosition(_ preserve: Bool) {
        hudViewController.setPreserveWindowPosition(preserve)
    }

    // MARK: - Private Setup

    private func setupBindings() {
        // The HUDViewController handles its own state binding to the store
        // This manager just provides the public interface for the app
    }
}
