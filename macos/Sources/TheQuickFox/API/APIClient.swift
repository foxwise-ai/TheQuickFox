//
//  APIClient.swift
//  TheQuickFox
//
//  Handles all API communication with the TheQuickFox backend
//

import Foundation
import os
import IOKit

enum APIError: Error {
    case invalidURL
    case noAuthToken
    case quotaExceeded
    case termsRequired
    case networkError(Error)
    case decodingError(Error)
    case serverError(String)
    case unauthorized
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL: String = {
        #if DEBUG
        return "http://localhost:4003/api/v1"
        #else
        return "https://api.thequickfox.ai/api/v1"
        #endif
    }()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TheQuickFox", category: "APIClient")
    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Network Monitor Helpers

    private func getHeaders(from request: URLRequest) -> [String: String] {
        request.allHTTPHeaderFields ?? [:]
    }

    private func getResponseHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return headers
    }

    // MARK: - Device Registration

    func registerDevice() async throws -> DeviceRegistrationResponse {
        // Get device info
        guard let deviceUUID = getDeviceUUID() else {
            throw APIError.invalidURL
        }

        let deviceName = Host.current().localizedName ?? "Mac"
        let request = DeviceRegistrationRequest(
            device_uuid: deviceUUID,
            device_name: deviceName
        )

        let url = URL(string: "\(baseURL)/devices/register")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createDeviceRegistrationEntry(
            url: url,
            headers: getHeaders(from: urlRequest),
            body: urlRequest.httpBody
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let registrationResponse = try decoder.decode(DeviceRegistrationResponse.self, from: data)
            // Store auth token in Keychain
            try KeychainManager.shared.saveAuthToken(registrationResponse.data.auth_token)
            // Update subscription status
            await UserSubscriptionManager.shared.updateFromDeviceRegistration(registrationResponse)

            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Device registered successfully"
            )
            return registrationResponse
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    // MARK: - Usage Tracking

    func trackUsage(mode: HUDMode, appInfo: ActiveWindowInfo? = nil, browserURL: String? = nil) async throws -> UsageTrackResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            // Try to register device first
            let registrationResponse = try await registerDevice()
            await UserSubscriptionManager.shared.updateFromDeviceRegistration(registrationResponse)
            guard let token = try KeychainManager.shared.getAuthToken() else {
                throw APIError.noAuthToken
            }
            return try await trackUsageWithToken(mode: mode, appInfo: appInfo, browserURL: browserURL, token: token)
        }

        return try await trackUsageWithToken(mode: mode, appInfo: appInfo, browserURL: browserURL, token: authToken)
    }

    private func trackUsageWithToken(mode: HUDMode, appInfo: ActiveWindowInfo?, browserURL: String?, token: String) async throws -> UsageTrackResponse {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        var metadata: [String: String] = [:]
        if let version = appVersion {
            metadata["app_version"] = version
        }

        let request = UsageTrackRequest(
            mode: mode.rawValue,
            app_name: appInfo?.appName,
            app_bundle_id: appInfo?.bundleID,
            window_title: appInfo?.windowTitle,
            url: browserURL,
            metadata: metadata.isEmpty ? nil : metadata
        )

        let url = URL(string: "\(baseURL)/usage/track")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(request)

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createUsageTrackingEntry(
            url: url,
            headers: getHeaders(from: urlRequest),
            body: urlRequest.httpBody
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let usageResponse = try decoder.decode(UsageTrackResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Usage tracked - \(usageResponse.data.trial_queries_remaining) queries remaining"
            )
            return usageResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        case 402:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data),
               errorResponse.upgrade_required == true {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Quota exceeded - upgrade required"
                )
                throw APIError.quotaExceeded
            }
            monitorEntry.fail(error: "Payment required")
            throw APIError.serverError("Payment required")
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                // Check for terms_required specifically
                if errorResponse.terms_required == true {
                    monitorEntry.complete(
                        statusCode: httpResponse.statusCode,
                        responseHeaders: getResponseHeaders(from: httpResponse),
                        responseBody: data,
                        responseSummary: "Terms acceptance required"
                    )
                    throw APIError.termsRequired
                }
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    // MARK: - Usage Status

    func getUsageStatus() async throws -> UsageStatusResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let url = URL(string: "\(baseURL)/usage")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createUsageStatusEntry(
            url: url,
            headers: getHeaders(from: urlRequest)
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let statusResponse = try decoder.decode(UsageStatusResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Status: \(statusResponse.data.trial_queries_remaining) queries remaining"
            )
            return statusResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    // MARK: - Analytics

    func getAnalyticsMetrics(timeRange: String = "30d") async throws -> AnalyticsMetricsResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        var urlComponents = URLComponents(string: "\(baseURL)/analytics/metrics")!
        urlComponents.queryItems = [URLQueryItem(name: "time_range", value: timeRange)]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createAnalyticsEntry(
            url: url,
            headers: getHeaders(from: urlRequest)
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let analyticsResponse = try decoder.decode(AnalyticsMetricsResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Analytics data retrieved"
            )
            return analyticsResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    // MARK: - Helpers

    private func getDeviceUUID() -> String? {
        // Get hardware UUID
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

    // MARK: - Stripe Checkout

    func createCheckoutSession(priceId: String) async throws -> StripeCheckoutResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let request = StripeCheckoutRequest(price_id: priceId)

        let url = URL(string: "\(baseURL)/stripe/checkout")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(request)

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createCheckoutEntry(
            url: url,
            headers: getHeaders(from: urlRequest),
            body: urlRequest.httpBody
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let checkoutResponse = try decoder.decode(StripeCheckoutResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Checkout session created"
            )
            return checkoutResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    // MARK: - Pricing

    func getPricing() async throws -> PricingResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let url = URL(string: "\(baseURL)/pricing")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createPricingEntry(
            url: url,
            headers: getHeaders(from: urlRequest)
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let pricingResponse = try decoder.decode(PricingResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Pricing data retrieved"
            )
            return pricingResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    // MARK: - Terms of Service

    func acceptTerms(email: String) async throws {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let request = AcceptTermsRequest(email: email)

        let url = URL(string: "\(baseURL)/users/accept-terms")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(request)

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createAcceptTermsEntry(
            url: url,
            headers: getHeaders(from: urlRequest),
            body: urlRequest.httpBody
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            print("✅ Terms accepted successfully for email: \(email)")
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Terms accepted successfully"
            )
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Failed to accept terms (status \(httpResponse.statusCode))")
            throw APIError.serverError("Failed to accept terms")
        }
    }

    // MARK: - Stripe Customer Portal

    func createCustomerPortalSession() async throws -> String {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let url = URL(string: "\(baseURL)/stripe/portal")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createPortalEntry(
            url: url,
            headers: getHeaders(from: urlRequest)
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let portalResponse = try decoder.decode(StripePortalResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Portal session created"
            )
            return portalResponse.data.portal_url
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }


    // MARK: - Bug Report

    func submitBugReport(_ submission: BugReportSubmission) async throws -> BugReportResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let url = URL(string: "\(baseURL)/feedback")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(submission)

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createBugReportEntry(
            url: url,
            headers: getHeaders(from: urlRequest),
            body: urlRequest.httpBody
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let bugReportResponse = try decoder.decode(BugReportResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Bug report submitted successfully"
            )
            return bugReportResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Unknown error (status \(httpResponse.statusCode))")
            throw APIError.serverError("Unknown error")
        }
    }

    func uploadLogFile(_ fileData: Data, feedbackId: String) async throws -> LogUploadResponse {
        guard let authToken = try KeychainManager.shared.getAuthToken() else {
            throw APIError.noAuthToken
        }

        let url = URL(string: "\(baseURL)/feedback/\(feedbackId)/logs")!

        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"logs\"; filename=\"debug_logs.zip\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Record request in network monitor
        let monitorEntry = NetworkMonitor.createLogUploadEntry(
            url: url,
            headers: getHeaders(from: request),
            fileSize: fileData.count
        )
        NetworkMonitor.shared.recordRequest(monitorEntry)
        monitorEntry.markInProgress()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            monitorEntry.fail(error: "Invalid response")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            let logUploadResponse = try decoder.decode(LogUploadResponse.self, from: data)
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Logs uploaded successfully"
            )
            return logUploadResponse
        case 401:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Unauthorized"
            )
            throw APIError.unauthorized
        case 400:
            monitorEntry.complete(
                statusCode: httpResponse.statusCode,
                responseHeaders: getResponseHeaders(from: httpResponse),
                responseBody: data,
                responseSummary: "Invalid file or file too large"
            )
            throw APIError.serverError("Invalid file or file too large")
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                monitorEntry.complete(
                    statusCode: httpResponse.statusCode,
                    responseHeaders: getResponseHeaders(from: httpResponse),
                    responseBody: data,
                    responseSummary: "Error: \(errorResponse.error)"
                )
                throw APIError.serverError(errorResponse.error)
            }
            monitorEntry.fail(error: "Upload failed (status \(httpResponse.statusCode))")
            throw APIError.serverError("Upload failed")
        }
    }
}
