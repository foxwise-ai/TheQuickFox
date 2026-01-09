//
//  MetricsReducer.swift
//  TheQuickFox
//
//  Handles metrics state changes
//

import Foundation

// MARK: - Metrics Reducer

func metricsReducer(_ state: MetricsState, _ action: MetricsAction) -> MetricsState {
    var newState = state

    switch action {
    case .startFetch:
        newState.isLoading = true

    case .updateData(let data):
        newState.data = data
        newState.lastFetchTime = Date()
        newState.isLoading = false

    case .fetchComplete:
        newState.isLoading = false

    case .fetchError(let error):
        newState.isLoading = false
        print("Metrics fetch error: \(error)")

    case .incrementQueryCount:
        newState.queriesSinceLastDisplay += 1

    case .resetQueryCount:
        newState.queriesSinceLastDisplay = 0

    case .showInHUD:
        // TODO: Re-enable when metrics HUD feature is ready
        // Disabled for now - still buggy
        break

    case .hideFromHUD:
        newState.showingInHUD = false
    }

    return newState
}
