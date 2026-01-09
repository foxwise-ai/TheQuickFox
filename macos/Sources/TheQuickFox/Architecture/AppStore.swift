//
//  AppStore.swift
//  TheQuickFox
//
//  Main application store implementing unidirectional data flow
//

import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: AppState

    // MARK: - Dependencies

    private let effectsHandler: EffectsHandler
    private let logger: StoreLogger

    // MARK: - Internal State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        initialState: AppState = .initial,
        effectsHandler: EffectsHandler = DefaultEffectsHandler(),
        logger: StoreLogger = ConsoleStoreLogger()
    ) {
        self.state = initialState
        self.effectsHandler = effectsHandler
        self.logger = logger

        setupEffectsHandler()
    }

    // MARK: - Public Interface

    func dispatch(_ action: AppAction) {
        let oldState = state

        // Log action
        logger.logAction(action, state: oldState)

        // Apply reducer
        state = appReducer(oldState, action)

        // Log state change (always log for now)
        // logger.logStateChange(from: oldState, to: state, action: action)

        // Handle side effects
        effectsHandler.handle(action: action, state: state, dispatch: dispatch)
    }

    // MARK: - Convenience Methods

    func showHUD() {
        dispatch(.showHUD())
    }

    func hideHUD() {
        dispatch(.hideHUD())
    }

    func submitQuery(_ query: String) {
        dispatch(.submitQuery(query))
    }

    func changeMode(_ mode: HUDMode) {
        dispatch(.changeMode(mode))
    }

    // MARK: - Private Methods

    private func setupEffectsHandler() {
        // The effects handler might need to dispatch actions back to the store
        // This creates the feedback loop for side effects
        effectsHandler.setDispatchFunction(dispatch)
    }
}

// MARK: - Store Access

extension AppStore {

    // Computed properties for easy access to sub-states
    var hudState: HUDState { state.hud }
    var historyState: HistoryState { state.history }
    var sessionState: SessionState { state.session }
    var subscriptionState: SubscriptionState { state.subscription }
    var toastState: ToastState { state.toast }

    // Publishers for specific state slices
    var hudStatePublisher: AnyPublisher<HUDState, Never> {
        $state.map(\.hud).eraseToAnyPublisher()
    }

    var historyStatePublisher: AnyPublisher<HistoryState, Never> {
        $state.map(\.history).eraseToAnyPublisher()
    }

    var sessionStatePublisher: AnyPublisher<SessionState, Never> {
        $state.map(\.session).eraseToAnyPublisher()
    }

    var subscriptionStatePublisher: AnyPublisher<SubscriptionState, Never> {
        $state.map(\.subscription).eraseToAnyPublisher()
    }

    var toastStatePublisher: AnyPublisher<ToastState, Never> {
        $state.map(\.toast).eraseToAnyPublisher()
    }
}

// MARK: - Singleton Access (for migration period)

extension AppStore {
    static let shared: AppStore = {
        MainActor.assumeIsolated {
            AppStore()
        }
    }()
}
