//
//  NetworkMonitor.swift
//  TheQuickFox
//
//  Central manager for monitoring all network requests.
//  Provides transparency for users to see exactly what data is sent/received.
//

import Foundation
import Combine
import AppKit

// MARK: - OCR Display Data

/// Parsed OCR data for display in the Network Monitor
public struct OCRDisplayData {
    public let texts: String
    public let observations: [Observation]
    public let latencyMs: Double

    public struct Observation {
        public let text: String
        public let confidence: Double
        public let quad: Quad?
    }

    public struct Quad {
        public let topLeft: CGPoint
        public let topRight: CGPoint
        public let bottomLeft: CGPoint
        public let bottomRight: CGPoint
    }

    /// Parse from JSON string (context_text format)
    public static func parse(from jsonString: String) -> OCRDisplayData? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let texts = json["texts"] as? String ?? json["text"] as? String ?? ""
        let latencyMs = json["latencyMs"] as? Double ?? 0

        var observations: [Observation] = []
        if let obsArray = json["observations"] as? [[String: Any]] {
            for obs in obsArray {
                let text = obs["text"] as? String ?? ""
                let confidence = obs["confidence"] as? Double ?? 0

                var quad: Quad? = nil
                if let quadDict = obs["quad"] as? [String: Any] {
                    if let tl = quadDict["topLeft"] as? [String: Double],
                       let tr = quadDict["topRight"] as? [String: Double],
                       let bl = quadDict["bottomLeft"] as? [String: Double],
                       let br = quadDict["bottomRight"] as? [String: Double] {
                        quad = Quad(
                            topLeft: CGPoint(x: tl["x"] ?? 0, y: tl["y"] ?? 0),
                            topRight: CGPoint(x: tr["x"] ?? 0, y: tr["y"] ?? 0),
                            bottomLeft: CGPoint(x: bl["x"] ?? 0, y: bl["y"] ?? 0),
                            bottomRight: CGPoint(x: br["x"] ?? 0, y: br["y"] ?? 0)
                        )
                    }
                }

                observations.append(Observation(text: text, confidence: confidence, quad: quad))
            }
        }

        return OCRDisplayData(texts: texts, observations: observations, latencyMs: latencyMs)
    }
}

// MARK: - Network Request Entry

/// Represents a single network request with its lifecycle
public class NetworkRequestEntry: ObservableObject, Identifiable {
    public let id = UUID()
    public let startTime: Date
    public let url: URL
    public let method: String
    public let endpoint: String  // Friendly endpoint name

    @Published public var status: RequestStatus
    @Published public var responseTime: TimeInterval?
    @Published public var statusCode: Int?
    @Published public var responseSize: Int?
    @Published public var error: String?

    // Request details
    public let requestHeaders: [String: String]
    public let requestBody: Data?
    public let requestBodySummary: String  // Human-readable summary

    // Response details
    @Published public var responseHeaders: [String: String]?
    @Published public var responseBody: Data?
    @Published public var responseSummary: String?  // Human-readable summary

    // Screenshot (extracted from request body for display)
    public var screenshotImage: NSImage?

    // OCR data (extracted from context_text JSON for display)
    public var ocrData: OCRDisplayData?

    // Metadata
    public let category: RequestCategory
    public let isSavedOnServer: Bool  // Indicates if this data is stored server-side
    public let serverDataDescription: String?  // What data is saved

    public enum RequestStatus: String {
        case pending = "Pending"
        case inProgress = "In Progress"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }

    public enum RequestCategory: String, CaseIterable {
        case authentication = "Authentication"
        case aiCompose = "AI Compose"
        case usage = "Usage Tracking"
        case analytics = "Analytics"
        case billing = "Billing"
        case feedback = "Feedback"
        case other = "Other"

        var icon: String {
            switch self {
            case .authentication: return "key.fill"
            case .aiCompose: return "brain"
            case .usage: return "chart.bar"
            case .analytics: return "chart.xyaxis.line"
            case .billing: return "creditcard"
            case .feedback: return "bubble.left"
            case .other: return "network"
            }
        }
    }

    public init(
        url: URL,
        method: String,
        endpoint: String,
        requestHeaders: [String: String],
        requestBody: Data?,
        requestBodySummary: String,
        category: RequestCategory,
        isSavedOnServer: Bool,
        serverDataDescription: String?
    ) {
        self.startTime = Date()
        self.url = url
        self.method = method
        self.endpoint = endpoint
        self.status = .pending
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestBodySummary = requestBodySummary
        self.category = category
        self.isSavedOnServer = isSavedOnServer
        self.serverDataDescription = serverDataDescription
    }

    func markInProgress() {
        DispatchQueue.main.async {
            self.status = .inProgress
        }
    }

    func complete(
        statusCode: Int,
        responseHeaders: [String: String],
        responseBody: Data?,
        responseSummary: String
    ) {
        DispatchQueue.main.async {
            self.status = .completed
            self.statusCode = statusCode
            self.responseTime = Date().timeIntervalSince(self.startTime)
            self.responseHeaders = responseHeaders
            self.responseBody = responseBody
            self.responseSummary = responseSummary
            self.responseSize = responseBody?.count
        }
    }

    func fail(error: String) {
        DispatchQueue.main.async {
            self.status = .failed
            self.error = error
            self.responseTime = Date().timeIntervalSince(self.startTime)
        }
    }

    func cancel() {
        DispatchQueue.main.async {
            self.status = .cancelled
            self.responseTime = Date().timeIntervalSince(self.startTime)
        }
    }
}

// MARK: - Network Monitor

/// Singleton manager for tracking all network requests
/// Only records when the monitor window is open - no background data accumulation.
/// Data is cleared when the window closes.
@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()

    /// All recorded requests (newest first) - only while window is open
    @Published public private(set) var requests: [NetworkRequestEntry] = []

    /// Maximum number of requests to keep while monitoring
    private let maxHistoryCount = 50

    /// Whether the monitor window is open (controls recording)
    @Published public private(set) var isMonitoring: Bool = false

    private init() {}

    /// Called when monitor window opens - start recording
    public func startMonitoring() {
        isMonitoring = true
        // Don't clear - let user see what's already there if they reopen quickly
    }

    /// Called when monitor window closes - stop recording and clear data
    public func stopMonitoring() {
        isMonitoring = false
        requests.removeAll()
    }

    // MARK: - Public API

    /// Record a new request (only if monitor window is open)
    public func recordRequest(_ entry: NetworkRequestEntry) {
        guard isMonitoring else { return }

        requests.insert(entry, at: 0)

        // Trim history if needed
        if requests.count > maxHistoryCount {
            requests = Array(requests.prefix(maxHistoryCount))
        }
    }

    // MARK: - Convenience Creators

    /// Create an entry for device registration
    public static func createDeviceRegistrationEntry(
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> NetworkRequestEntry {
        var summary = "Registering device with server"
        if let body = body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let deviceName = json["device_name"] as? String {
                summary = "Registering device: \(deviceName)"
            }
        }

        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Device Registration",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: summary,
            category: .authentication,
            isSavedOnServer: true,
            serverDataDescription: "Device UUID and name are stored to identify your device"
        )
    }

    /// Create an entry for usage tracking
    public static func createUsageTrackingEntry(
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> NetworkRequestEntry {
        var summary = "Recording query usage"
        if let body = body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let mode = json["mode"] as? String {
                summary = "Recording \(mode) mode usage"
            }
        }

        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Usage Tracking",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: summary,
            category: .usage,
            isSavedOnServer: true,
            serverDataDescription: "Query mode, app name, and timestamp are stored for usage analytics"
        )
    }

    /// Create an entry for compose/AI requests
    public static func createComposeEntry(
        url: URL,
        headers: [String: String],
        body: Data?,
        mode: String
    ) -> NetworkRequestEntry {
        var summary = "Sending context for AI response"
        var hasScreenshot = false
        var screenshotImage: NSImage? = nil
        var ocrData: OCRDisplayData? = nil

        if let body = body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            // Extract screenshot if present
            if let base64String = json["screenshot_base64"] as? String,
               let imageData = Data(base64Encoded: base64String),
               let image = NSImage(data: imageData) {
                hasScreenshot = true
                screenshotImage = image
            }

            // Extract OCR data from context_text
            if let contextText = json["context_text"] as? String {
                ocrData = OCRDisplayData.parse(from: contextText)
            }

            if let query = json["query"] as? String, !query.isEmpty {
                let truncated = query.prefix(50)
                summary = "Query: \"\(truncated)\(query.count > 50 ? "..." : "")\""
            }
        }

        let entry = NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "AI Compose (\(mode))",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: summary + (hasScreenshot ? " (with screenshot)" : ""),
            category: .aiCompose,
            isSavedOnServer: false,  // AI queries are processed but not stored
            serverDataDescription: nil
        )
        entry.screenshotImage = screenshotImage
        entry.ocrData = ocrData
        return entry
    }

    /// Create an entry for analytics requests
    public static func createAnalyticsEntry(
        url: URL,
        headers: [String: String]
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "GET",
            endpoint: "Analytics Metrics",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: nil,
            requestBodySummary: "Fetching your usage statistics",
            category: .analytics,
            isSavedOnServer: false,  // Just reading, not saving new data
            serverDataDescription: nil
        )
    }

    /// Create an entry for usage status requests
    public static func createUsageStatusEntry(
        url: URL,
        headers: [String: String]
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "GET",
            endpoint: "Usage Status",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: nil,
            requestBodySummary: "Checking remaining queries",
            category: .usage,
            isSavedOnServer: false,
            serverDataDescription: nil
        )
    }

    /// Create an entry for billing/checkout requests
    public static func createCheckoutEntry(
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Stripe Checkout",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: "Creating payment session",
            category: .billing,
            isSavedOnServer: false,  // Payment handled by Stripe
            serverDataDescription: nil
        )
    }

    /// Create an entry for pricing requests
    public static func createPricingEntry(
        url: URL,
        headers: [String: String]
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "GET",
            endpoint: "Pricing",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: nil,
            requestBodySummary: "Fetching subscription pricing",
            category: .billing,
            isSavedOnServer: false,
            serverDataDescription: nil
        )
    }

    /// Create an entry for customer portal requests
    public static func createPortalEntry(
        url: URL,
        headers: [String: String]
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Stripe Portal",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: nil,
            requestBodySummary: "Opening subscription management",
            category: .billing,
            isSavedOnServer: false,
            serverDataDescription: nil
        )
    }

    /// Create an entry for bug report submission
    public static func createBugReportEntry(
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> NetworkRequestEntry {
        var summary = "Submitting bug report"
        if let body = body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = json["message"] as? String {
            let truncated = message.prefix(50)
            summary = "Bug report: \"\(truncated)\(message.count > 50 ? "..." : "")\""
        }

        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Bug Report",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: summary,
            category: .feedback,
            isSavedOnServer: true,
            serverDataDescription: "Bug report message and system info are stored for support"
        )
    }

    /// Create an entry for log upload
    public static func createLogUploadEntry(
        url: URL,
        headers: [String: String],
        fileSize: Int
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Log Upload",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: nil,
            requestBodySummary: "Uploading debug logs (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))",
            category: .feedback,
            isSavedOnServer: true,
            serverDataDescription: "Debug logs are stored to help diagnose issues"
        )
    }

    /// Create an entry for terms acceptance
    public static func createAcceptTermsEntry(
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: "POST",
            endpoint: "Accept Terms",
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: "Accepting terms of service",
            category: .authentication,
            isSavedOnServer: true,
            serverDataDescription: "Email and acceptance timestamp are stored"
        )
    }

    /// Create a generic entry for unknown endpoints
    public static func createGenericEntry(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) -> NetworkRequestEntry {
        return NetworkRequestEntry(
            url: url,
            method: method,
            endpoint: url.lastPathComponent,
            requestHeaders: sanitizeHeaders(headers),
            requestBody: body,
            requestBodySummary: "API request to \(url.lastPathComponent)",
            category: .other,
            isSavedOnServer: false,
            serverDataDescription: nil
        )
    }

    // MARK: - Helpers

    /// Remove sensitive headers (auth tokens) for display
    private static func sanitizeHeaders(_ headers: [String: String]) -> [String: String] {
        var sanitized = headers
        if let auth = sanitized["Authorization"] {
            // Show that auth is present but hide the actual token
            if auth.hasPrefix("Bearer ") {
                sanitized["Authorization"] = "Bearer [REDACTED]"
            } else {
                sanitized["Authorization"] = "[REDACTED]"
            }
        }
        return sanitized
    }
}

// MARK: - Response Helpers

extension NetworkRequestEntry {
    /// Parse response body as JSON for display
    public var responseJSON: Any? {
        guard let data = responseBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Parse request body as JSON for display
    public var requestJSON: Any? {
        guard let data = requestBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Formatted request body for display
    public var formattedRequestBody: String {
        guard let data = requestBody else { return "(no body)" }

        // Try to format as JSON
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           var prettyString = String(data: prettyData, encoding: .utf8) {
            // Redact screenshot data for readability
            if prettyString.contains("screenshot_base64") {
                prettyString = prettyString.replacingOccurrences(
                    of: #""screenshot_base64"\s*:\s*"[^"]*""#,
                    with: "\"screenshot_base64\": \"[See Screenshot Sent section above]\"",
                    options: .regularExpression
                )
            }
            // Redact context_text (OCR data) for readability
            if prettyString.contains("context_text"), ocrData != nil {
                prettyString = prettyString.replacingOccurrences(
                    of: #""context_text"\s*:\s*"[^"]*""#,
                    with: "\"context_text\": \"[See OCR Context Sent section above]\"",
                    options: .regularExpression
                )
            }
            return prettyString
        }

        // Fall back to raw string
        return String(data: data, encoding: .utf8) ?? "(binary data: \(formatBytes(data.count)))"
    }

    /// Formatted response body for display
    public var formattedResponseBody: String {
        guard let data = responseBody else { return "(no response body)" }

        // Try to format as JSON
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }

        // Fall back to raw string
        return String(data: data, encoding: .utf8) ?? "(binary data: \(formatBytes(data.count)))"
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
