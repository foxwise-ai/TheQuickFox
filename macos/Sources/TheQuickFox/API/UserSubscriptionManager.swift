//
//  UserSubscriptionManager.swift
//  TheQuickFox
//
//  Manages user subscription status
//

import Foundation

@MainActor
final class UserSubscriptionManager: ObservableObject {
    static let shared: UserSubscriptionManager = {
        MainActor.assumeIsolated {
            UserSubscriptionManager()
        }
    }()

    @Published private(set) var hasActiveSubscription: Bool = false
    @Published private(set) var trialQueriesRemaining: Int = 0
    @Published private(set) var subscriptionDetails: SubscriptionDetails?

    private init() {}

    /// Update subscription status from API responses
    func updateFromDeviceRegistration(_ response: DeviceRegistrationResponse) {
        self.hasActiveSubscription = response.data.has_subscription
        self.trialQueriesRemaining = response.data.trial_queries_remaining
        self.subscriptionDetails = response.data.subscription_details
    }

    func updateFromUsageStatus(_ response: UsageStatusResponse) {
        self.hasActiveSubscription = response.data.has_subscription
        self.trialQueriesRemaining = response.data.trial_queries_remaining
        self.subscriptionDetails = response.data.subscription_details
    }
    
    /// Get formatted subscription description
    var formattedSubscriptionInfo: String {
        guard let details = subscriptionDetails else {
            return hasActiveSubscription ? "Active subscription" : ""
        }

        switch details.type {
        case "subscription":
            if let interval = details.interval,
               let amount = details.amount,
               let currency = details.currency {
                let price = formatPrice(amount: amount, currency: currency)
                let period = interval == "month" ? "monthly" : "yearly"
                return "Unlimited queries • \(price)/\(period)"
            }
            return "Unlimited queries • Active subscription"
        case "trial":
            return "\(details.trial_queries_remaining ?? trialQueriesRemaining) trial queries remaining"
        default:
            return ""
        }
    }
    
    private func formatPrice(amount: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        let dollars = Double(amount) / 100.0
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}