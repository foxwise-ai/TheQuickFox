//
//  LoggingSystem.swift
//  TheQuickFox
//
//  Master logging system that coordinates all logging components.
//  Provides a unified interface for production logging with privacy controls.
//

import Foundation
import os

// MARK: - Privacy Level

public enum PrivacyLevel: String, CaseIterable {
    case minimal = "minimal"     // Only errors and warnings, no user data
    case standard = "standard"   // Normal logging with PII scrubbing  
    case detailed = "detailed"   // Full debugging info with sensitive data
    
    public var filterConfig: LogFilterConfig {
        switch self {
        case .minimal:
            return LogFilterConfig(
                minLevel: .warning,
                includeSuccessfulFlows: false,
                maxEntries: 50,
                relevanceThreshold: 0.6
            )
        case .standard:
            return .default
        case .detailed:
            return .debugging
        }
    }
    
    public var includeSensitiveData: Bool {
        return self == .detailed
    }
}

// MARK: - Logging System Configuration

public struct LoggingSystemConfig {
    public let enableProductionLogging: Bool
    public let enableAggregation: Bool
    public let privacyLevel: PrivacyLevel
    public let maxStorageSize: Int // MB
    public let autoExportOnCrash: Bool
    public let shareWithTelemetry: Bool
    
    public static let production = LoggingSystemConfig(
        enableProductionLogging: true,
        enableAggregation: true,
        privacyLevel: .standard,
        maxStorageSize: 50,
        autoExportOnCrash: true,
        shareWithTelemetry: false
    )
    
    public static let development = LoggingSystemConfig(
        enableProductionLogging: true,
        enableAggregation: true,
        privacyLevel: .detailed,
        maxStorageSize: 200,
        autoExportOnCrash: false,
        shareWithTelemetry: false
    )
    
    public static let minimal = LoggingSystemConfig(
        enableProductionLogging: true,
        enableAggregation: false,
        privacyLevel: .minimal,
        maxStorageSize: 10,
        autoExportOnCrash: false,
        shareWithTelemetry: false
    )
}

// MARK: - Master Logging System

public final class LoggingSystem {
    
    public static let shared = LoggingSystem()
    
    // MARK: - Configuration
    
    public var config: LoggingSystemConfig {
        didSet {
            updateConfiguration()
        }
    }
    
    // MARK: - Components
    
    private let productionLogger = ProductionLogger.shared
    private let aggregator = LogAggregator.shared
    private let filter = LogFilter.shared
    private let exportManager = LogExportManager.shared
    private let legacyLogger = LoggingManager.shared
    
    // MARK: - State
    
    private var currentSessionId: UUID?
    private let queue = DispatchQueue(label: "LoggingSystem")
    private var isInitialized = false
    
    private init() {
        // Determine initial config based on environment
        if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
            self.config = .development
        } else {
            self.config = .production
        }
        
        initialize()
    }
    
    // MARK: - Initialization
    
    private func initialize() {
        queue.async { [weak self] in
            guard let self = self, !self.isInitialized else { return }
            
            self.isInitialized = true
            
            // Set up crash handling if enabled
            if self.config.autoExportOnCrash {
                self.setupCrashHandler()
            }
            
            // Start log aggregation if enabled
            if self.config.enableAggregation {
                self.startLogAggregation()
            }
            
            self.log(.info, .generic, "Logging system initialized", metadata: [
                "config": AnyCodable(self.config.privacyLevel.rawValue),
                "production_enabled": AnyCodable(self.config.enableProductionLogging),
                "aggregation_enabled": AnyCodable(self.config.enableAggregation)
            ])
        }
    }
    
    private func updateConfiguration() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.log(.info, .generic, "Logging configuration updated", metadata: [
                "privacy_level": AnyCodable(self.config.privacyLevel.rawValue),
                "storage_limit_mb": AnyCodable(self.config.maxStorageSize)
            ])
        }
    }
    
    // MARK: - Session Management
    
    /// Start a new logging session (typically triggered by user action)
    @discardableResult
    public func startSession(trigger: String, metadata: [String: AnyCodable]? = nil) -> UUID {
        let sessionId = productionLogger.startSession(trigger: trigger)
        
        queue.async { [weak self] in
            self?.currentSessionId = sessionId
        }
        
        log(.info, .generic, "User session started", sessionId: sessionId, metadata: metadata)
        
        return sessionId
    }
    
    /// End the current logging session
    public func endSession(outcome: SessionOutcome, metadata: [String: AnyCodable]? = nil) {
        let sessionId = currentSessionId
        
        productionLogger.endSession(outcome: outcome)
        
        queue.async { [weak self] in
            self?.currentSessionId = nil
        }
        
        log(.info, .generic, "User session ended", sessionId: sessionId, metadata: metadata)
    }
    
    // MARK: - Primary Logging Interface
    
    /// Main logging method - automatically respects privacy settings
    public func log(
        _ level: LogLevel,
        _ category: LogCategory,
        _ message: String,
        sessionId: UUID? = nil,
        metadata: [String: AnyCodable]? = nil,
        error: Error? = nil
    ) {
        // Use current session if none specified
        let effectiveSessionId = sessionId ?? currentSessionId
        
        // Apply privacy filtering
        let (sanitizedMessage, sanitizedMetadata) = sanitizeData(
            message: message,
            metadata: metadata,
            level: config.privacyLevel
        )
        
        // Log to production logger if enabled
        if config.enableProductionLogging {
            productionLogger.log(
                level,
                category,
                sanitizedMessage,
                sessionId: effectiveSessionId,
                metadata: sanitizedMetadata,
                error: error
            )
        }
        
        // Also log to legacy system for dev console output
        legacyLogger.log(level.osLogType, category, sanitizedMessage)
    }
    
    // MARK: - Convenience Methods
    
    public func logError(_ category: LogCategory, _ error: Error, sessionId: UUID? = nil, metadata: [String: AnyCodable]? = nil) {
        log(.error, category, "Error occurred", sessionId: sessionId, metadata: metadata, error: error)
    }
    
    public func logWarning(_ category: LogCategory, _ message: String, sessionId: UUID? = nil, metadata: [String: AnyCodable]? = nil) {
        log(.warning, category, message, sessionId: sessionId, metadata: metadata)
    }
    
    public func logInfo(_ category: LogCategory, _ message: String, sessionId: UUID? = nil, metadata: [String: AnyCodable]? = nil) {
        log(.info, category, message, sessionId: sessionId, metadata: metadata)
    }
    
    public func logDebug(_ category: LogCategory, _ message: String, sessionId: UUID? = nil, metadata: [String: AnyCodable]? = nil) {
        log(.debug, category, message, sessionId: sessionId, metadata: metadata)
    }
    
    // MARK: - Performance Logging
    
    /// Log performance metrics
    public func logPerformance(
        _ category: LogCategory,
        operation: String,
        duration: TimeInterval,
        sessionId: UUID? = nil,
        additionalMetrics: [String: AnyCodable]? = nil
    ) {
        var metadata: [String: AnyCodable] = [
            "operation": AnyCodable(operation),
            "duration_ms": AnyCodable(Int(duration * 1000))
        ]
        
        if let additional = additionalMetrics {
            metadata.merge(additional) { _, new in new }
        }
        
        let level: LogLevel = duration > 5.0 ? .warning : .info
        let message = "Performance: \(operation) took \(String(format: "%.2f", duration))s"
        
        log(level, category, message, sessionId: sessionId, metadata: metadata)
    }
    
    // MARK: - Export and Sharing
    
    /// Quick export for user sharing
    public func exportLogsForSharing(
        issueDescription: String? = nil,
        completion: @escaping (String?) -> Void
    ) {
        exportManager.quickExport(issueDescription: issueDescription, completion: completion)
    }
    
    /// Export with save dialog
    public func exportLogsWithDialog(completion: @escaping (LogExportResult) -> Void) {
        let options = LogExportOptions(
            format: .text,
            filterConfig: config.privacyLevel.filterConfig,
            includeSystemInfo: true,
            includeSensitiveData: config.privacyLevel.includeSensitiveData
        )
        
        exportManager.exportWithSaveDialog(options: options, completion: completion)
    }
    
    /// Email logs to support
    public func emailLogsToSupport(issueDescription: String? = nil) {
        let options = LogExportOptions(
            format: .text,
            filterConfig: config.privacyLevel.filterConfig,
            includeSystemInfo: true,
            includeSensitiveData: false // Never include sensitive data in emails
        )
        
        exportManager.emailLogs(
            issueDescription: issueDescription,
            options: options
        )
    }
    
    // MARK: - Analysis and Debugging
    
    /// Get recent error flows for debugging
    public func getRecentErrorFlows(hours: Int = 24) -> [AggregatedLogFlow] {
        guard config.enableAggregation else { return [] }
        
        let since = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        return aggregator.getErrorFlows(since: since)
    }
    
    /// Generate analysis report
    public func generateAnalysisReport(hours: Int = 24) -> FlowAnalysisReport? {
        guard config.enableAggregation else { return nil }
        
        let since = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        return aggregator.generateAnalysisReport(since: since)
    }
    
    // MARK: - Privacy and Data Sanitization
    
    private func sanitizeData(
        message: String,
        metadata: [String: AnyCodable]?,
        level: PrivacyLevel
    ) -> (String, [String: AnyCodable]?) {
        
        switch level {
        case .detailed:
            // No sanitization in detailed mode
            return (message, metadata)
            
        case .standard:
            // Standard PII scrubbing
            let sanitizedMessage = scrubPII(from: message)
            let sanitizedMetadata = metadata?.compactMapValues { value in
                if let stringValue = value.value as? String {
                    return AnyCodable(scrubPII(from: stringValue))
                }
                return value
            }
            return (sanitizedMessage, sanitizedMetadata)
            
        case .minimal:
            // Minimal info only
            let sanitizedMessage = scrubPII(from: message, aggressive: true)
            let filteredMetadata = metadata?.filter { key, _ in
                !["query", "response", "context", "screenshot"].contains(key.lowercased())
            }
            return (sanitizedMessage, filteredMetadata)
        }
    }
    
    private func scrubPII(from text: String, aggressive: Bool = false) -> String {
        var scrubbed = text
        
        // Email addresses
        scrubbed = scrubbed.replacingOccurrences(
            of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
            with: "[EMAIL]",
            options: .regularExpression
        )
        
        // Phone numbers
        scrubbed = scrubbed.replacingOccurrences(
            of: #"\b\d{3}-\d{3}-\d{4}\b|\b\(\d{3}\)\s?\d{3}-\d{4}\b"#,
            with: "[PHONE]",
            options: .regularExpression
        )
        
        // Credit card numbers (basic pattern)
        scrubbed = scrubbed.replacingOccurrences(
            of: #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#,
            with: "[CARD]",
            options: .regularExpression
        )
        
        // URLs with sensitive params
        scrubbed = scrubbed.replacingOccurrences(
            of: #"[?&](key|token|auth|api[_-]?key|password)[=][^&\s]+"#,
            with: "?$1=[REDACTED]",
            options: .regularExpression
        )
        
        if aggressive {
            // In minimal mode, also scrub file paths and user names
            scrubbed = scrubbed.replacingOccurrences(
                of: #"/Users/[^/\s]+/"#,
                with: "/Users/[USER]/",
                options: .regularExpression
            )
            
            // Remove long text that might contain user content
            if scrubbed.count > 200 {
                scrubbed = String(scrubbed.prefix(200)) + "...[truncated]"
            }
        }
        
        return scrubbed
    }
    
    // MARK: - Background Processing
    
    private func startLogAggregation() {
        // Periodically process logs for aggregation
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.processLogsForAggregation()
        }
    }
    
    private func processLogsForAggregation() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Get recent logs and process them
            let exported = self.productionLogger.exportLogs(minLevel: .debug, lastHours: 1)
            self.aggregator.processLogEntries(exported.entries)
        }
    }
    
    // MARK: - Crash Handling
    
    private func setupCrashHandler() {
        // Set up crash detection and auto-export
        // This would integrate with crash reporting frameworks
        
        NSSetUncaughtExceptionHandler { exception in
            LoggingSystem.shared.handleCrash(exception: exception)
        }
    }
    
    private func handleCrash(exception: NSException) {
        // Auto-export logs on crash
        let options = LogExportOptions(
            format: .text,
            filterConfig: LogFilterConfig(
                minLevel: .warning,
                timeWindow: 3600,
                maxEntries: 100,
                relevanceThreshold: 0.5
            ),
            includeSystemInfo: true,
            includeSensitiveData: false
        )
        
        exportManager.exportLogs(options: options) { result in
            if result.success {
                // Logs exported for post-crash analysis
                print("Crash logs exported to: \(result.fileURL?.path ?? "unknown")")
            }
        }
        
        log(.critical, .generic, "Application crash detected", metadata: [
            "exception": AnyCodable(exception.name.rawValue),
            "reason": AnyCodable(exception.reason ?? "unknown")
        ])
    }
}

// MARK: - Extensions

extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}