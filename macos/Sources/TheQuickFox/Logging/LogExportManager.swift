//
//  LogExportManager.swift
//  TheQuickFox
//
//  User-facing log export and sharing functionality.
//  Provides easy ways for users to share debugging information with support.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Export Format

public enum LogExportFormat: String, CaseIterable {
    case text = "text"
    case json = "json"
    case csv = "csv"
    case markdown = "markdown"
    
    public var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .json: return "json"  
        case .csv: return "csv"
        case .markdown: return "md"
        }
    }
    
    public var mimeType: String {
        switch self {
        case .text: return "text/plain"
        case .json: return "application/json"
        case .csv: return "text/csv"
        case .markdown: return "text/markdown"
        }
    }
}

// MARK: - Export Options

public struct LogExportOptions {
    public let format: LogExportFormat
    public let filterConfig: LogFilterConfig
    public let includeSystemInfo: Bool
    public let includeSensitiveData: Bool
    public let compressOutput: Bool
    public let filename: String?
    
    public static let supportTicket = LogExportOptions(
        format: .text,
        filterConfig: .errorOnly,
        includeSystemInfo: true,
        includeSensitiveData: false,
        compressOutput: true,
        filename: nil
    )
    
    public static let debugging = LogExportOptions(
        format: .json,
        filterConfig: .debugging,
        includeSystemInfo: true,
        includeSensitiveData: true,
        compressOutput: false,
        filename: nil
    )
    
    public static let quickShare = LogExportOptions(
        format: .text,
        filterConfig: LogFilterConfig(
            minLevel: .warning,
            timeWindow: 3600, // Last hour
            maxEntries: 30,
            relevanceThreshold: 0.5
        ),
        includeSystemInfo: true,
        includeSensitiveData: false,
        compressOutput: false,
        filename: nil
    )
    
    public init(
        format: LogExportFormat = .text,
        filterConfig: LogFilterConfig = .default,
        includeSystemInfo: Bool = true,
        includeSensitiveData: Bool = false,
        compressOutput: Bool = false,
        filename: String? = nil
    ) {
        self.format = format
        self.filterConfig = filterConfig
        self.includeSystemInfo = includeSystemInfo
        self.includeSensitiveData = includeSensitiveData
        self.compressOutput = compressOutput
        self.filename = filename
    }
}

// MARK: - Export Result

public struct LogExportResult {
    public let success: Bool
    public let fileURL: URL?
    public let error: Error?
    public let stats: ExportStats
    public let shareableText: String? // For quick copy/paste
}

public struct ExportStats {
    public let entriesExported: Int
    public let flowsExported: Int
    public let fileSizeBytes: Int
    public let exportDuration: TimeInterval
    public let formatUsed: LogExportFormat
}

// MARK: - Log Export Manager

public final class LogExportManager {
    
    public static let shared = LogExportManager()
    
    private let productionLogger = ProductionLogger.shared
    private let aggregator = LogAggregator.shared
    private let filter = LogFilter.shared
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Export API
    
    /// Export logs with specified options - main export method
    public func exportLogs(
        options: LogExportOptions,
        completion: @escaping (LogExportResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let startTime = Date()
            
            do {
                // Get recent logs and flows
                let exported = self.productionLogger.exportLogs(
                    minLevel: options.filterConfig.minLevel,
                    lastHours: Int((options.filterConfig.timeWindow ?? 86400) / 3600)
                )
                
                let flows = self.aggregator.getRecentFlows(count: 100)
                
                // Apply filtering
                let filtered = self.filter.filterLogs(
                    entries: exported.entries,
                    flows: flows,
                    config: options.filterConfig
                )
                
                // Generate export data
                let exportData = self.generateExportData(
                    filtered: filtered,
                    exported: exported,
                    options: options
                )
                
                // Write to file
                let fileURL = try self.writeExportToFile(
                    data: exportData,
                    options: options
                )
                
                let stats = ExportStats(
                    entriesExported: filtered.entries.count,
                    flowsExported: filtered.flows.count,
                    fileSizeBytes: exportData.count,
                    exportDuration: Date().timeIntervalSince(startTime),
                    formatUsed: options.format
                )
                
                // Generate shareable text for quick copy/paste
                let shareableText = options.format == .text ? 
                    String(data: exportData, encoding: .utf8) : nil
                
                let result = LogExportResult(
                    success: true,
                    fileURL: fileURL,
                    error: nil,
                    stats: stats,
                    shareableText: shareableText
                )
                
                DispatchQueue.main.async {
                    completion(result)
                }
                
            } catch {
                let result = LogExportResult(
                    success: false,
                    fileURL: nil,
                    error: error,
                    stats: ExportStats(
                        entriesExported: 0,
                        flowsExported: 0,
                        fileSizeBytes: 0,
                        exportDuration: Date().timeIntervalSince(startTime),
                        formatUsed: options.format
                    ),
                    shareableText: nil
                )
                
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }
    
    /// Quick export for immediate sharing (returns text directly)
    public func quickExport(
        issueDescription: String? = nil,
        completion: @escaping (String?) -> Void
    ) {
        let options = LogExportOptions.quickShare
        
        exportLogs(options: options) { result in
            if result.success, let shareableText = result.shareableText {
                var output = shareableText
                
                if let description = issueDescription {
                    output = "Issue: \(description)\n\n" + output
                }
                
                completion(output)
            } else {
                completion(nil)
            }
        }
    }
    
    /// Export and show save dialog
    public func exportWithSaveDialog(
        options: LogExportOptions,
        completion: @escaping (LogExportResult) -> Void
    ) {
        exportLogs(options: options) { result in
            guard result.success, let fileURL = result.fileURL else {
                completion(result)
                return
            }
            
            DispatchQueue.main.async {
                let savePanel = NSSavePanel()
                savePanel.title = "Export TheQuickFox Logs"
                savePanel.nameFieldStringValue = self.defaultFilename(for: options)
                savePanel.allowedContentTypes = [self.contentType(for: options.format)]
                
                if savePanel.runModal() == .OK,
                   let destinationURL = savePanel.url {
                    
                    do {
                        // Move file to user-selected location
                        if self.fileManager.fileExists(atPath: destinationURL.path) {
                            try self.fileManager.removeItem(at: destinationURL)
                        }
                        try self.fileManager.moveItem(at: fileURL, to: destinationURL)
                        
                        let updatedResult = LogExportResult(
                            success: result.success,
                            fileURL: destinationURL,
                            error: result.error,
                            stats: result.stats,
                            shareableText: result.shareableText
                        )
                        completion(updatedResult)
                        
                    } catch {
                        let failedResult = LogExportResult(
                            success: false,
                            fileURL: result.fileURL,
                            error: error,
                            stats: result.stats,
                            shareableText: result.shareableText
                        )
                        completion(failedResult)
                    }
                } else {
                    // User cancelled - clean up temp file
                    try? self.fileManager.removeItem(at: fileURL)
                    completion(result)
                }
            }
        }
    }
    
    /// Copy logs to clipboard
    public func copyToClipboard(
        options: LogExportOptions = .quickShare,
        completion: @escaping (Bool) -> Void
    ) {
        exportLogs(options: options) { result in
            guard result.success, let shareableText = result.shareableText else {
                completion(false)
                return
            }
            
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(shareableText, forType: .string)
                completion(true)
            }
        }
    }
    
    // MARK: - Mail Integration
    
    /// Compose email with logs attached
    public func emailLogs(
        to recipient: String = "support@thequickfox.com",
        subject: String = "TheQuickFox Debug Logs",
        issueDescription: String? = nil,
        options: LogExportOptions = .supportTicket
    ) {
        exportLogs(options: options) { result in
            guard result.success, let fileURL = result.fileURL else { return }
            
            DispatchQueue.main.async {
                self.composeEmail(
                    to: recipient,
                    subject: subject,
                    body: self.generateEmailBody(issueDescription: issueDescription, stats: result.stats),
                    attachmentURL: fileURL
                )
            }
        }
    }
    
    // MARK: - Preset Exports
    
    /// Export for GitHub issue
    public func exportForGitHubIssue(completion: @escaping (String?) -> Void) {
        let options = LogExportOptions(
            format: .markdown,
            filterConfig: LogFilterConfig(
                minLevel: .warning,
                timeWindow: 3600,
                maxEntries: 50,
                relevanceThreshold: 0.4
            ),
            includeSystemInfo: true,
            includeSensitiveData: false
        )
        
        exportLogs(options: options) { result in
            completion(result.shareableText)
        }
    }
    
    /// Export for developer debugging
    public func exportForDebugging(completion: @escaping (LogExportResult) -> Void) {
        exportWithSaveDialog(options: .debugging, completion: completion)
    }
    
    // MARK: - Format Generation
    
    private func generateExportData(
        filtered: FilteredLogResult,
        exported: ExportedLogs,
        options: LogExportOptions
    ) -> Data {
        switch options.format {
        case .text:
            return generateTextFormat(filtered: filtered, exported: exported, options: options)
        case .json:
            return generateJSONFormat(filtered: filtered, exported: exported, options: options)
        case .csv:
            return generateCSVFormat(filtered: filtered, exported: exported, options: options)
        case .markdown:
            return generateMarkdownFormat(filtered: filtered, exported: exported, options: options)
        }
    }
    
    private func generateTextFormat(filtered: FilteredLogResult, exported: ExportedLogs, options: LogExportOptions) -> Data {
        var content = """
            TheQuickFox Debug Export
            =======================
            Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .full))
            Format: Plain Text
            
            """
        
        if options.includeSystemInfo {
            content += """
                System Information:
                - Device: \(exported.deviceInfo.model)
                - OS: \(exported.deviceInfo.osVersion)
                - App Version: \(exported.deviceInfo.appVersion)
                
                """
        }
        
        content += """
            Export Summary:
            - Total entries processed: \(filtered.totalEntriesBeforeFilter)
            - Entries included: \(filtered.entries.count)
            - Flows included: \(filtered.flows.count)
            - Errors: \(filtered.summary.errorCount)
            - Warnings: \(filtered.summary.warningCount)
            - Time span: \(String(format: "%.1f", filtered.summary.timeSpan / 3600)) hours
            
            """
        
        if !filtered.summary.topErrorTypes.isEmpty {
            content += "Top Error Types:\n"
            for errorType in filtered.summary.topErrorTypes {
                content += "- \(errorType)\n"
            }
            content += "\n"
        }
        
        if !filtered.summary.recommendedActions.isEmpty {
            content += "Recommendations:\n"
            for action in filtered.summary.recommendedActions {
                content += "- \(action)\n"
            }
            content += "\n"
        }
        
        content += "Log Entries:\n"
        content += "============\n\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        for entry in filtered.entries {
            let sessionTag = entry.sessionId.map { "[\(String($0.uuidString.prefix(8)))]" } ?? "[no-session]"
            content += "[\(formatter.string(from: entry.timestamp))] \(entry.level.rawValue.uppercased()) \(entry.category) \(sessionTag)\n"
            content += "   \(entry.message)\n"
            
            if let error = entry.error {
                content += "   Error: \(error.type)\n"
                content += "   Description: \(error.description)\n"
                if let code = error.code {
                    content += "   Code: \(code)\n"
                }
            }
            
            // Always include metadata for error entries (for debugging), or when sensitive data is allowed
            if let metadata = entry.metadata, !metadata.isEmpty {
                if options.includeSensitiveData || (entry.error != nil) {
                    content += "   Metadata:\n"
                    for (key, value) in metadata {
                        content += "     \(key): \(value)\n"
                    }
                }
            }
            
            content += "\n"
        }
        
        return content.data(using: .utf8) ?? Data()
    }
    
    private func generateJSONFormat(filtered: FilteredLogResult, exported: ExportedLogs, options: LogExportOptions) -> Data {
        var exportData: [String: Any] = [
            "export_info": [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "format": "json",
                "version": "1.0"
            ],
            "summary": [
                "entries_processed": filtered.totalEntriesBeforeFilter,
                "entries_included": filtered.entries.count,
                "flows_included": filtered.flows.count,
                "errors": filtered.summary.errorCount,
                "warnings": filtered.summary.warningCount,
                "time_span_hours": filtered.summary.timeSpan / 3600,
                "top_error_types": filtered.summary.topErrorTypes,
                "recommendations": filtered.summary.recommendedActions
            ]
        ]
        
        if options.includeSystemInfo {
            exportData["system_info"] = [
                "device_model": exported.deviceInfo.model,
                "os_version": exported.deviceInfo.osVersion,
                "app_version": exported.deviceInfo.appVersion
            ]
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            // Create entries data
            let entriesData = try encoder.encode(filtered.entries)
            if let entriesJSON = try JSONSerialization.jsonObject(with: entriesData) as? [[String: Any]] {
                exportData["entries"] = entriesJSON
            }
            
            // Create flows data  
            let flowsData = try encoder.encode(filtered.flows)
            if let flowsJSON = try JSONSerialization.jsonObject(with: flowsData) as? [[String: Any]] {
                exportData["flows"] = flowsJSON
            }
            
            return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        } catch {
            // Fallback to basic JSON if encoding fails
            return try! JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        }
    }
    
    private func generateCSVFormat(filtered: FilteredLogResult, exported: ExportedLogs, options: LogExportOptions) -> Data {
        var csv = "timestamp,level,category,session_id,message,error_type,error_description\n"
        
        let formatter = ISO8601DateFormatter()
        
        for entry in filtered.entries {
            let timestamp = formatter.string(from: entry.timestamp)
            let level = entry.level.rawValue
            let category = entry.category
            let sessionId = entry.sessionId?.uuidString ?? ""
            let message = csvEscape(entry.message)
            let errorType = csvEscape(entry.error?.type ?? "")
            let errorDescription = csvEscape(entry.error?.description ?? "")
            
            csv += "\(timestamp),\(level),\(category),\(sessionId),\(message),\(errorType),\(errorDescription)\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
    
    private func generateMarkdownFormat(filtered: FilteredLogResult, exported: ExportedLogs, options: LogExportOptions) -> Data {
        var markdown = """
            # TheQuickFox Debug Export
            
            **Generated:** \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .full))
            
            """
        
        if options.includeSystemInfo {
            markdown += """
                ## System Information
                
                - **Device:** \(exported.deviceInfo.model)
                - **OS:** \(exported.deviceInfo.osVersion)  
                - **App Version:** \(exported.deviceInfo.appVersion)
                
                """
        }
        
        markdown += """
            ## Summary
            
            - **Total entries processed:** \(filtered.totalEntriesBeforeFilter)
            - **Entries included:** \(filtered.entries.count)
            - **Flows included:** \(filtered.flows.count)
            - **Errors:** \(filtered.summary.errorCount)
            - **Warnings:** \(filtered.summary.warningCount)
            - **Time span:** \(String(format: "%.1f", filtered.summary.timeSpan / 3600)) hours
            
            """
        
        if !filtered.summary.topErrorTypes.isEmpty {
            markdown += "### Top Error Types\n\n"
            for errorType in filtered.summary.topErrorTypes {
                markdown += "- `\(errorType)`\n"
            }
            markdown += "\n"
        }
        
        if !filtered.summary.recommendedActions.isEmpty {
            markdown += "### Recommendations\n\n"
            for action in filtered.summary.recommendedActions {
                markdown += "- \(action)\n"
            }
            markdown += "\n"
        }
        
        markdown += "## Log Entries\n\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        
        for entry in filtered.entries {
            let sessionTag = entry.sessionId.map { String($0.uuidString.prefix(8)) } ?? "no-session"
            
            markdown += """
                ### [\(formatter.string(from: entry.timestamp))] \(entry.level.emoji) \(entry.category) `\(sessionTag)`
                
                \(entry.message)
                
                """
            
            if let error = entry.error {
                markdown += """
                    **Error:** `\(error.type)`  
                    **Description:** \(error.description)
                    
                    """
            }
            
            if options.includeSensitiveData, let metadata = entry.metadata, !metadata.isEmpty {
                markdown += "**Metadata:**\n```\n"
                for (key, value) in metadata {
                    markdown += "\(key): \(value)\n"
                }
                markdown += "```\n\n"
            }
        }
        
        return markdown.data(using: .utf8) ?? Data()
    }
    
    // MARK: - File Operations
    
    private func writeExportToFile(data: Data, options: LogExportOptions) throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let filename = options.filename ?? defaultFilename(for: options)
        let fileURL = tempDir.appendingPathComponent(filename)
        
        if options.compressOutput {
            // Simple compression would go here - for now just write as-is
            try data.write(to: fileURL)
        } else {
            try data.write(to: fileURL)
        }
        
        return fileURL
    }
    
    private func defaultFilename(for options: LogExportOptions) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let prefix = "thequickfox_logs"
        let suffix = options.format.fileExtension
        
        return "\(prefix)_\(timestamp).\(suffix)"
    }
    
    private func contentType(for format: LogExportFormat) -> UTType {
        switch format {
        case .text: return .plainText
        case .json: return .json
        case .csv: return .commaSeparatedText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
    
    // MARK: - Email Composition
    
    private func composeEmail(to recipient: String, subject: String, body: String, attachmentURL: URL) {
        let mailto = "mailto:\(recipient)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: mailto) {
            NSWorkspace.shared.open(url)
        }
        
        // Also reveal the attachment file for manual attachment
        NSWorkspace.shared.selectFile(attachmentURL.path, inFileViewerRootedAtPath: "")
    }
    
    private func generateEmailBody(issueDescription: String?, stats: ExportStats) -> String {
        var body = """
            Hi,
            
            I'm experiencing an issue with TheQuickFox and have attached debug logs for investigation.
            
            """
        
        if let description = issueDescription {
            body += "Issue Description:\n\(description)\n\n"
        }
        
        body += """
            Debug Information:
            - Log entries: \(stats.entriesExported)
            - Export format: \(stats.formatUsed.rawValue)
            - Export duration: \(String(format: "%.2f", stats.exportDuration))s
            
            Please let me know if you need any additional information.
            
            Thanks,
            """
        
        return body
    }
    
    // MARK: - Utilities
    
    private func csvEscape(_ string: String) -> String {
        let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}