//
//  SubscriptionReducer.swift
//  TheQuickFox
//
//  Handles subscription state changes
//

import Foundation

// MARK: - Subscription Reducer

func subscriptionReducer(_ state: SubscriptionState, _ action: SubscriptionAction) -> SubscriptionState {
    var newState = state
    
    switch action {
    case .startFetch:
        newState.isLoading = true
        
    case .updateFromDeviceRegistration(let response):
        newState.hasActiveSubscription = response.data.has_subscription
        newState.trialQueriesRemaining = response.data.trial_queries_remaining
        newState.subscriptionDetails = response.data.subscription_details
        newState.isLoading = false
        newState.lastFetchTime = Date()

    case .updateFromUsageStatus(let response):
        newState.hasActiveSubscription = response.data.has_subscription
        newState.trialQueriesRemaining = response.data.trial_queries_remaining
        newState.subscriptionDetails = response.data.subscription_details
        newState.isLoading = false
        newState.lastFetchTime = Date()
        
    case .fetchComplete:
        newState.isLoading = false
        
    case .fetchError(let error):
        newState.isLoading = false
        print("Subscription fetch error: \(error)")
    }
    
    return newState
}