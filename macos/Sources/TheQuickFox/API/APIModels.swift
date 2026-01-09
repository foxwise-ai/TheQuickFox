//
//  APIModels.swift
//  TheQuickFox
//
//  API request and response models for the TheQuickFox backend
//

import Foundation
import IOKit

// MARK: - Device Registration

struct DeviceRegistrationRequest: Encodable {
    let device_uuid: String
    let device_name: String
}

struct DeviceRegistrationResponse: Decodable {
    let data: DeviceData

    struct DeviceData: Decodable {
        let device_id: Int
        let user_id: Int
        let auth_token: String
        let trial_queries_used: Int
        let trial_queries_remaining: Int
        let has_subscription: Bool
        let subscription_details: SubscriptionDetails?
    }
}

// MARK: - Usage Tracking

struct UsageTrackRequest: Encodable {
    let mode: String
    let app_name: String?
    let app_bundle_id: String?
    let window_title: String?
    let url: String?  // For browser URLs when available
    let metadata: [String: String]?
}

struct UsageTrackResponse: Decodable {
    let data: UsageData

    struct UsageData: Decodable {
        let query_id: Int
        let tracked_at: String
        let trial_queries_remaining: Int
    }
}

// MARK: - Usage Status

struct UsageStatusResponse: Decodable {
    let data: StatusData

    struct StatusData: Decodable {
        let trial_queries_used: Int
        let trial_queries_remaining: Int
        let queries_today: Int
        let has_subscription: Bool
        let subscription_details: SubscriptionDetails?
    }
}

// MARK: - Subscription Details

struct SubscriptionDetails: Decodable {
    let type: String  // "subscription" or "trial"
    let interval: String?  // "month" or "year" for subscriptions
    let interval_count: Int?  // 1 for monthly, 1 for yearly
    let amount: Int?  // Amount in cents
    let currency: String?  // Currency code (e.g., "usd")
    let cancel_at_period_end: Bool?
    let trial_queries_remaining: Int?
}

// MARK: - Error Response

struct APIErrorResponse: Decodable {
    let error: String
    let upgrade_required: Bool?
    let terms_required: Bool?
}

// MARK: - Accept Terms

struct AcceptTermsRequest: Encodable {
    let email: String
}

// MARK: - Stripe Checkout

struct StripeCheckoutRequest: Encodable {
    let price_id: String
}

struct StripeCheckoutResponse: Decodable {
    let data: CheckoutData

    struct CheckoutData: Decodable {
        let checkout_url: String
        let session_id: String
    }
}

// MARK: - Pricing

struct PricingResponse: Codable {
    let data: PricingData
}

struct PricingData: Codable {
    let prices: [Price]
    let trial: TrialInfo
}

struct Price: Codable {
    let price_id: String
    let product_id: String
    let amount: Int
    let currency: String
    let interval: String
    let interval_count: Int
    let name: String?
    let description: String?
    let metadata: [String: String]?
    let display_price: String
    let features: [String]  // Make non-optional to ensure it's always present
}

struct TrialInfo: Codable {
    let queries_limit: Int
    let queries_used: Int
    let queries_remaining: Int
}

// MARK: - Stripe Portal

struct StripePortalResponse: Decodable {
    let data: PortalData

    struct PortalData: Decodable {
        let portal_url: String
    }
}

// MARK: - Analytics

struct AnalyticsMetricsResponse: Decodable {
    let data: AnalyticsData
}

struct SystemInfo: Encodable {
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let locale: String
    
    static func current() -> SystemInfo {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel = Host.current().localizedName ?? "Mac"
        let locale = Locale.current.identifier
        
        return SystemInfo(
            appVersion: appVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            locale: locale
        )
    }
}

// MARK: - Bug Report

struct BugReportSubmission: Encodable {
    let message: String
    let category: String
    let device_id: String?
    let app_version: String?
    let os_version: String?
    let timestamp: String?
    
    static func create(message: String) -> BugReportSubmission {
        let systemInfo = SystemInfo.current()
        return BugReportSubmission(
            message: message,
            category: "bug",
            device_id: getDeviceUUID(),
            app_version: systemInfo.appVersion,
            os_version: systemInfo.osVersion,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    private static func getDeviceUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard platformExpert > 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }
        
        guard let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as? String else {
            return nil
        }
        
        return serialNumber
    }
}

struct BugReportResponse: Decodable {
    let success: Bool
    let feedback_id: String?
    let message: String
}

struct LogUploadResponse: Decodable {
    let success: Bool
    let message: String
}
