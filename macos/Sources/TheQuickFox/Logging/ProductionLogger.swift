//
//  ProductionLogger.swift
//  TheQuickFox
//
//  Comprehensive logging system for production issue reproduction.
//  Stores structured, correlatable logs with privacy controls and export functionality.
//
//  Usage:
//      let logger = ProductionLogger.shared
//      let sessionId = logger.startSession(trigger: "double_control")
//      logger.log(.screenshot, "Screenshot captured", sessionId: sessionId, metadata: ["pixels": pixels])
//      logger.logError(.pipeline, error, sessionId: sessionId)
//      logger.exportLogs() // For user sharing
//

import Foundation
import os

// MARK: - Production Log Entry

public struct ProductionLogEntry: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let sessionId: UUID?
    public let category: String
    public let level: LogLevel
    public let message: String
    public let metadata: [String: AnyCodable]?
    public let error: ErrorInfo?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionId: UUID?,
        category: LogCategory,
        level: LogLevel,
        message: String,
        metadata: [String: AnyCodable]? = nil,
        error: ErrorInfo? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.category = category.rawValue
        self.level = level
        self.message = message
        self.metadata = metadata
        self.error = error
    }
}

public struct ErrorInfo: Codable {
    public let type: String
    public let description: String
    public let code: Int?
    public let domain: String?
    
    public init(from error: Error) {
        self.type = String(describing: Swift.type(of: error))
        self.description = error.localizedDescription
        
        if let nsError = error as NSError? {
            self.code = nsError.code
            self.domain = nsError.domain
        } else {
            self.code = nil
            self.domain = nil
        }
    }
}

public enum LogLevel: String, CaseIterable, Codable, Comparable {
    case debug = "debug"
    case info = "info" 
    case warning = "warning"
    case error = "error"
    case critical = "critical"
    
    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .critical: return 4
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❗️"
        case .critical: return "🔥"
        }
    }
    
    // Comparable implementation
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.priority < rhs.priority
    }
}

// MARK: - Session Context

public struct SessionContext: Codable {
    public let id: UUID
    public let startTime: Date
    public let trigger: String // "double_control", "menu_click", etc
    public var endTime: Date?
    public var outcome: SessionOutcome?
    public let appVersion: String
    public let osVersion: String
    public let deviceModel: String
    
    public init(trigger: String) {
        self.id = UUID()
        self.startTime = Date()
        self.trigger = trigger
        self.endTime = nil
        self.outcome = nil
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.deviceModel = ProcessInfo.processInfo.machineDescription
    }
}

public enum SessionOutcome: String, Codable {
    case success = "success"
    case userCancelled = "user_cancelled"  
    case error = "error"
    case quotaExceeded = "quota_exceeded"
    case permissionDenied = "permission_denied"
}

// MARK: - Production Logger

public final class ProductionLogger {
    
    public static let shared = ProductionLogger()
    
    // MARK: - Configuration
    
    private struct Config {
        static let maxEntries = 1000
        static let maxSessionAge: TimeInterval = 24 * 60 * 60 // 24 hours
        static let logFileName = "thequickfox.log"
        static let sessionFileName = "sessions.log"
    }
    
    // MARK: - Private State
    
    private let queue = DispatchQueue(label: "ProductionLogger", qos: .utility)
    private let fileManager = FileManager.default
    private var currentSession: SessionContext?
    private let isEnabled: Bool
    
    private lazy var logsDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TheQuickFox")
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("logs")
    }()
    
    private lazy var logFileURL: URL = {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        return logsDirectory.appendingPathComponent(Config.logFileName)
    }()
    
    private lazy var sessionFileURL: URL = {
        return logsDirectory.appendingPathComponent(Config.sessionFileName)
    }()
    
    private init() {
        self.isEnabled = true // Always enabled in production
        
        // Cleanup old logs on startup
        queue.async { [weak self] in
            self?.cleanupOldLogs()
        }
    }
    
    // MARK: - Session Management
    
    /// Starts a new logging session, returning the session ID for correlation
    @discardableResult
    public func startSession(trigger: String) -> UUID {
        let session = SessionContext(trigger: trigger)
        
        queue.async { [weak self] in
            self?.currentSession = session
            self?.writeSession(session)
        }
        
        log(.info, .generic, "Session started", sessionId: session.id, metadata: [
            "trigger": AnyCodable(trigger),
            "app_version": AnyCodable(session.appVersion),
            "os_version": AnyCodable(session.osVersion)
        ])
        
        return session.id
    }
    
    /// Ends the current session with an outcome
    public func endSession(outcome: SessionOutcome) {
        queue.async { [weak self] in
            guard var session = self?.currentSession else { return }
            
            session.endTime = Date()
            session.outcome = outcome
            self?.currentSession = session
            self?.writeSession(session)
            
            self?.log(.info, .generic, "Session ended", sessionId: session.id, metadata: [
                "outcome": AnyCodable(outcome.rawValue),
                "duration": AnyCodable(Date().timeIntervalSince(session.startTime))
            ])
        }
    }
    
    // MARK: - Logging API
    
    /// Primary logging method
    public func log(
        _ level: LogLevel,
        _ category: LogCategory,
        _ message: String,
        sessionId: UUID? = nil,
        metadata: [String: AnyCodable]? = nil,
        error: Error? = nil
    ) {
        guard isEnabled else { return }
        
        let entry = ProductionLogEntry(
            sessionId: sessionId ?? currentSession?.id,
            category: category,
            level: level,
            message: message,
            metadata: metadata,
            error: error.map(ErrorInfo.init)
        )
        
        queue.async { [weak self] in
            self?.writeLogEntry(entry)
        }
        
        // Also mirror to console in dev mode
        if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
            let sessionInfo = sessionId.map { " [\($0.uuidString.prefix(8))]" } ?? ""
            print("\(level.emoji) [\(category.rawValue)]\(sessionInfo) \(message)")
            
            if let error = error {
                print("   Error: \(error.localizedDescription)")
            }
            
            if let metadata = metadata, !metadata.isEmpty {
                let metadataStr = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                print("   Metadata: \(metadataStr)")
            }
        }
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
    
    // MARK: - Export and Retrieval
    
    /// Export logs for user sharing - returns sanitized log data
    public func exportLogs(minLevel: LogLevel = .info, lastHours: Int = 24) -> ExportedLogs {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastHours * 3600))
        
        let logs = queue.sync {
            return loadLogEntries()
                .filter { $0.timestamp > cutoff }
                .filter { $0.level.priority >= minLevel.priority }
        }
        
        let sessions = queue.sync {
            return loadSessions()
                .filter { $0.startTime > cutoff }
        }
        
        return ExportedLogs(
            exportTime: Date(),
            deviceInfo: DeviceInfo(),
            sessions: sessions,
            entries: logs.map { sanitizeLogEntry($0) }
        )
    }
    
    /// Export logs as formatted text for easy sharing
    public func exportLogsAsText(minLevel: LogLevel = .info, lastHours: Int = 24) -> String {
        let exported = exportLogs(minLevel: minLevel, lastHours: lastHours)
        return formatExportedLogs(exported)
    }
    
    // MARK: - File Operations
    
    private func writeLogEntry(_ entry: ProductionLogEntry) {
        do {
            let data = try JSONEncoder().encode(entry)
            let line = String(data: data, encoding: .utf8)! + "\n"
            
            if fileManager.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { handle.closeFile() }
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
            } else {
                try line.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
            
            // Rotate logs if needed
            rotateLogsIfNeeded()
            
        } catch {
            print("Failed to write log entry: \(error)")
        }
    }
    
    private func writeSession(_ session: SessionContext) {
        do {
            let data = try JSONEncoder().encode(session)
            let line = String(data: data, encoding: .utf8)! + "\n"
            
            if fileManager.fileExists(atPath: sessionFileURL.path) {
                let handle = try FileHandle(forWritingTo: sessionFileURL)
                defer { handle.closeFile() }
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
            } else {
                try line.write(to: sessionFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write session: \(error)")
        }
    }
    
    private func loadLogEntries() -> [ProductionLogEntry] {
        guard let content = try? String(contentsOf: logFileURL) else { return [] }
        
        let decoder = JSONDecoder()
        return content.components(separatedBy: .newlines)
            .compactMap { line -> ProductionLogEntry? in
                guard !line.isEmpty,
                      let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(ProductionLogEntry.self, from: data)
            }
    }
    
    private func loadSessions() -> [SessionContext] {
        guard let content = try? String(contentsOf: sessionFileURL) else { return [] }
        
        let decoder = JSONDecoder()
        return content.components(separatedBy: .newlines)
            .compactMap { line -> SessionContext? in
                guard !line.isEmpty,
                      let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionContext.self, from: data)
            }
    }
    
    private func rotateLogsIfNeeded() {
        // Keep only recent logs to prevent unbounded growth
        let entries = loadLogEntries()
        if entries.count > Config.maxEntries {
            let recentEntries = Array(entries.suffix(Config.maxEntries / 2))
            rewriteLogFile(with: recentEntries)
        }
    }
    
    private func rewriteLogFile(with entries: [ProductionLogEntry]) {
        do {
            try? fileManager.removeItem(at: logFileURL)
            
            let encoder = JSONEncoder()
            for entry in entries {
                let data = try encoder.encode(entry)
                let line = String(data: data, encoding: .utf8)! + "\n"
                
                if fileManager.fileExists(atPath: logFileURL.path) {
                    let handle = try FileHandle(forWritingTo: logFileURL)
                    defer { handle.closeFile() }
                    handle.seekToEndOfFile()
                    handle.write(line.data(using: .utf8)!)
                } else {
                    try line.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("Failed to rotate logs: \(error)")
        }
    }
    
    private func cleanupOldLogs() {
        let cutoff = Date().addingTimeInterval(-Config.maxSessionAge)
        
        // Clean up old log entries
        let entries = loadLogEntries().filter { $0.timestamp > cutoff }
        rewriteLogFile(with: entries)
        
        // Clean up old sessions  
        let sessions = loadSessions().filter { $0.startTime > cutoff }
        do {
            try? fileManager.removeItem(at: sessionFileURL)
            
            let encoder = JSONEncoder()
            for session in sessions {
                let data = try encoder.encode(session)
                let line = String(data: data, encoding: .utf8)! + "\n"
                
                if fileManager.fileExists(atPath: sessionFileURL.path) {
                    let handle = try FileHandle(forWritingTo: sessionFileURL)
                    defer { handle.closeFile() }
                    handle.seekToEndOfFile()
                    handle.write(line.data(using: .utf8)!)
                } else {
                    try line.write(to: sessionFileURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("Failed to cleanup sessions: \(error)")
        }
    }
    
    // MARK: - Privacy and Sanitization
    
    private func sanitizeLogEntry(_ entry: ProductionLogEntry) -> ProductionLogEntry {
        // Remove sensitive data while preserving debugging info
        var sanitizedMetadata = entry.metadata
        
        // Remove API keys, tokens, etc.
        let sensitiveKeys = ["api_key", "token", "auth", "password", "secret"]
        for key in sensitiveKeys {
            if sanitizedMetadata?.keys.contains(where: { $0.lowercased().contains(key.lowercased()) }) == true {
                sanitizedMetadata?[key] = AnyCodable("[REDACTED]")
            }
        }
        
        // Truncate very long metadata values
        sanitizedMetadata = sanitizedMetadata?.mapValues { value in
            if let stringValue = value.value as? String, stringValue.count > 500 {
                return AnyCodable(String(stringValue.prefix(500)) + "...[truncated]")
            }
            return value
        }
        
        return ProductionLogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            sessionId: entry.sessionId,
            category: LogCategory(rawValue: entry.category) ?? .generic,
            level: entry.level,
            message: entry.message,
            metadata: sanitizedMetadata,
            error: entry.error
        )
    }
    
    private func formatExportedLogs(_ exported: ExportedLogs) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var output = """
            TheQuickFox Debug Logs
            ======================
            Export Time: \(formatter.string(from: exported.exportTime))
            Device: \(exported.deviceInfo.model)
            OS: \(exported.deviceInfo.osVersion)
            App: \(exported.deviceInfo.appVersion)
            
            SESSIONS (\(exported.sessions.count)):
            
            """
        
        for session in exported.sessions.sorted(by: { $0.startTime > $1.startTime }) {
            let duration = session.endTime?.timeIntervalSince(session.startTime) ?? 0
            let outcome = session.outcome?.rawValue ?? "ongoing"
            output += "[\(formatter.string(from: session.startTime))] \(session.trigger) → \(outcome) (\(String(format: "%.1f", duration))s)\n"
        }
        
        output += "\nLOGS (\(exported.entries.count)):\n\n"
        
        for entry in exported.entries.sorted(by: { $0.timestamp > $1.timestamp }) {
            let sessionTag = entry.sessionId.map { "[\(String($0.uuidString.prefix(8)))]" } ?? "[no-session]"
            output += "[\(formatter.string(from: entry.timestamp))] \(entry.level.emoji) \(entry.category) \(sessionTag) \(entry.message)\n"
            
            if let error = entry.error {
                output += "   Error: \(error.type) - \(error.description)\n"
            }
            
            if let metadata = entry.metadata, !metadata.isEmpty {
                let metadataStr = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                output += "   \(metadataStr)\n"
            }
            
            output += "\n"
        }
        
        return output
    }
}

// MARK: - Supporting Types

public struct ExportedLogs: Codable {
    public let exportTime: Date
    public let deviceInfo: DeviceInfo
    public let sessions: [SessionContext]
    public let entries: [ProductionLogEntry]
}

public struct DeviceInfo: Codable {
    public let model: String
    public let osVersion: String
    public let appVersion: String
    
    public init() {
        self.model = ProcessInfo.processInfo.machineDescription
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(Bool.self) {
            self.value = value
        } else {
            self.value = "unknown"
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let value = value as? String {
            try container.encode(value)
        } else if let value = value as? Int {
            try container.encode(value)
        } else if let value = value as? Double {
            try container.encode(value)
        } else if let value = value as? Bool {
            try container.encode(value)
        } else {
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - ProcessInfo Extension

extension ProcessInfo {
    var machineDescription: String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}