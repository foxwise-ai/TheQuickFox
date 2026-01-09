//
//  LogFilter.swift
//  TheQuickFox
//
//  Intelligent log filtering system that shows only relevant information.
//  Reduces noise and highlights important events for debugging.
//

import Foundation

// MARK: - Filter Configuration

public struct LogFilterConfig {
    public let minLevel: LogLevel
    public let includeCategories: Set<LogCategory>?
    public let excludeCategories: Set<LogCategory>?
    public let timeWindow: TimeInterval?
    public let sessionId: UUID?
    public let includeSuccessfulFlows: Bool
    public let maxEntries: Int
    public let relevanceThreshold: Double
    
    public static let `default` = LogFilterConfig(
        minLevel: .info,
        includeCategories: nil,
        excludeCategories: nil, 
        timeWindow: 86400, // 24 hours
        sessionId: nil,
        includeSuccessfulFlows: false,
        maxEntries: 100,
        relevanceThreshold: 0.3
    )
    
    public static let debugging = LogFilterConfig(
        minLevel: .debug,
        includeCategories: nil,
        excludeCategories: Set([.generic]),
        timeWindow: 3600, // 1 hour
        sessionId: nil,
        includeSuccessfulFlows: true,
        maxEntries: 500,
        relevanceThreshold: 0.1
    )
    
    public static let errorOnly = LogFilterConfig(
        minLevel: .error,
        includeCategories: nil,
        excludeCategories: nil,
        timeWindow: 86400 * 7, // 1 week
        sessionId: nil,
        includeSuccessfulFlows: false,
        maxEntries: 200,
        relevanceThreshold: 0.8
    )
    
    public init(
        minLevel: LogLevel = .info,
        includeCategories: Set<LogCategory>? = nil,
        excludeCategories: Set<LogCategory>? = nil,
        timeWindow: TimeInterval? = nil,
        sessionId: UUID? = nil,
        includeSuccessfulFlows: Bool = false,
        maxEntries: Int = 100,
        relevanceThreshold: Double = 0.3
    ) {
        self.minLevel = minLevel
        self.includeCategories = includeCategories
        self.excludeCategories = excludeCategories
        self.timeWindow = timeWindow
        self.sessionId = sessionId
        self.includeSuccessfulFlows = includeSuccessfulFlows
        self.maxEntries = maxEntries
        self.relevanceThreshold = relevanceThreshold
    }
}

// MARK: - Filtered Log Result

public struct FilteredLogResult {
    public let entries: [ProductionLogEntry]
    public let flows: [AggregatedLogFlow]
    public let summary: FilterSummary
    public let appliedFilters: LogFilterConfig
    public let totalEntriesBeforeFilter: Int
}

public struct FilterSummary {
    public let entriesShown: Int
    public let entriesFiltered: Int
    public let errorCount: Int
    public let warningCount: Int
    public let sessionsAffected: Int
    public let timeSpan: TimeInterval
    public let topErrorTypes: [String]
    public let recommendedActions: [String]
}

// MARK: - Relevance Scoring

public struct RelevanceScore {
    public let entry: ProductionLogEntry
    public let score: Double
    public let reasons: [RelevanceReason]
}

public enum RelevanceReason: Codable {
    case error(severity: String)
    case performance(metric: String, threshold: Double)
    case userImpact(description: String)
    case systemState(change: String)
    case correlation(relatedTo: String)
    case pattern(matches: String)
}

// MARK: - Log Filter

public final class LogFilter {
    
    public static let shared = LogFilter()
    
    // MARK: - Filtering Keywords and Patterns
    
    private struct FilterPatterns {
        // High relevance patterns (always include)
        static let critical = [
            "pipeline failed", "quota exceeded", "permission denied", 
            "crash", "abort", "fatal", "critical error", "system error",
            "timeout", "network error", "api error", "authentication failed"
        ]
        
        // Performance indicators
        static let performance = [
            "slow", "timeout", "retry", "failed to", "taking longer",
            "bottleneck", "memory", "cpu", "disk space"
        ]
        
        // User-facing issues
        static let userImpact = [
            "user cancelled", "insertion failed", "focus lost", "window not found",
            "clipboard", "paste failed", "no response", "empty result"
        ]
        
        // System state changes
        static let systemState = [
            "session started", "session ended", "mode changed", "permission",
            "window appeared", "app switched", "screenshot captured"
        ]
        
        // Noise patterns (usually exclude)
        static let noise = [
            "debug trace", "heartbeat", "polling", "routine check",
            "periodic", "background", "keepalive", "maintenance"
        ]
        
        // Verbose patterns (lower priority)
        static let verbose = [
            "processing token", "stream chunk", "partial response",
            "intermediate result", "buffer update"
        ]
    }
    
    private init() {}
    
    // MARK: - Main Filtering API
    
    /// Filter log entries with smart relevance scoring
    public func filterLogs(
        entries: [ProductionLogEntry],
        flows: [AggregatedLogFlow]? = nil,
        config: LogFilterConfig = .default
    ) -> FilteredLogResult {
        
        let totalEntries = entries.count
        
        // Step 1: Basic filtering (level, category, time)
        let basicFiltered = applyBasicFilters(entries, config: config)
        
        // Step 2: Calculate relevance scores
        let scoredEntries = calculateRelevanceScores(basicFiltered, flows: flows)
        
        // Step 3: Apply relevance threshold
        let relevantEntries = scoredEntries
            .filter { $0.score >= config.relevanceThreshold }
            .sorted { $0.score > $1.score } // Highest relevance first
        
        // Step 4: Limit to max entries and sort chronologically for exports
        let finalEntries = Array(relevantEntries.prefix(config.maxEntries))
            .map { $0.entry }
            .sorted { $0.timestamp < $1.timestamp } // Chronological order
        
        // Step 5: Filter flows if provided
        let filteredFlows = filterFlows(flows ?? [], config: config)
        
        // Step 6: Generate summary
        let summary = generateFilterSummary(
            originalCount: totalEntries,
            filteredEntries: finalEntries,
            filteredFlows: filteredFlows,
            config: config
        )
        
        return FilteredLogResult(
            entries: finalEntries,
            flows: filteredFlows,
            summary: summary,
            appliedFilters: config,
            totalEntriesBeforeFilter: totalEntries
        )
    }
    
    /// Get smart filter suggestions based on recent log patterns
    public func suggestFilterConfig(for entries: [ProductionLogEntry]) -> [LogFilterConfig] {
        var suggestions: [LogFilterConfig] = []
        
        let errorCount = entries.filter { $0.level >= .error }.count
        let warningCount = entries.filter { $0.level == .warning }.count
        let totalCount = entries.count
        
        // If high error rate, suggest error-focused filter
        if totalCount > 0 && Double(errorCount) / Double(totalCount) > 0.1 {
            suggestions.append(.errorOnly)
        }
        
        // If lots of warnings, suggest warning+ filter  
        if totalCount > 0 && Double(warningCount + errorCount) / Double(totalCount) > 0.2 {
            suggestions.append(LogFilterConfig(
                minLevel: .warning,
                timeWindow: 3600,
                includeSuccessfulFlows: false,
                maxEntries: 200,
                relevanceThreshold: 0.4
            ))
        }
        
        // If user debugging, suggest comprehensive filter
        if entries.contains(where: { $0.message.lowercased().contains("debug") }) {
            suggestions.append(.debugging)
        }
        
        // Default suggestion
        if suggestions.isEmpty {
            suggestions.append(.default)
        }
        
        return suggestions
    }
    
    // MARK: - Basic Filtering
    
    private func applyBasicFilters(_ entries: [ProductionLogEntry], config: LogFilterConfig) -> [ProductionLogEntry] {
        let now = Date()
        
        return entries.filter { entry in
            // Level filter
            guard entry.level.priority >= config.minLevel.priority else { return false }
            
            // Category filters
            let category = LogCategory(rawValue: entry.category) ?? .generic
            
            if let includeCategories = config.includeCategories {
                guard includeCategories.contains(category) else { return false }
            }
            
            if let excludeCategories = config.excludeCategories {
                guard !excludeCategories.contains(category) else { return false }
            }
            
            // Time window filter
            if let timeWindow = config.timeWindow {
                guard now.timeIntervalSince(entry.timestamp) <= timeWindow else { return false }
            }
            
            // Session filter
            if let sessionId = config.sessionId {
                guard entry.sessionId == sessionId else { return false }
            }
            
            return true
        }
    }
    
    // MARK: - Relevance Scoring
    
    private func calculateRelevanceScores(_ entries: [ProductionLogEntry], flows: [AggregatedLogFlow]?) -> [RelevanceScore] {
        return entries.map { entry in
            let score = calculateRelevance(for: entry, in: flows)
            return RelevanceScore(entry: entry, score: score.score, reasons: score.reasons)
        }
    }
    
    private func calculateRelevance(for entry: ProductionLogEntry, in flows: [AggregatedLogFlow]?) -> (score: Double, reasons: [RelevanceReason]) {
        var score = 0.0
        var reasons: [RelevanceReason] = []
        let message = entry.message.lowercased()
        
        // Base score from log level
        switch entry.level {
        case .critical:
            score += 1.0
            reasons.append(.error(severity: "critical"))
        case .error:
            score += 0.8
            reasons.append(.error(severity: "error"))
        case .warning:
            score += 0.4
            reasons.append(.error(severity: "warning"))
        case .info:
            score += 0.2
        case .debug:
            score += 0.1
        }
        
        // Pattern matching for high-relevance content
        for pattern in FilterPatterns.critical {
            if message.contains(pattern) {
                score += 0.8
                reasons.append(.pattern(matches: pattern))
                break
            }
        }
        
        for pattern in FilterPatterns.performance {
            if message.contains(pattern) {
                score += 0.6
                reasons.append(.performance(metric: pattern, threshold: 5.0))
                break
            }
        }
        
        for pattern in FilterPatterns.userImpact {
            if message.contains(pattern) {
                score += 0.7
                reasons.append(.userImpact(description: pattern))
                break
            }
        }
        
        for pattern in FilterPatterns.systemState {
            if message.contains(pattern) {
                score += 0.3
                reasons.append(.systemState(change: pattern))
                break
            }
        }
        
        // Reduce score for noise patterns
        for pattern in FilterPatterns.noise {
            if message.contains(pattern) {
                score -= 0.4
                break
            }
        }
        
        for pattern in FilterPatterns.verbose {
            if message.contains(pattern) {
                score -= 0.2
                break
            }
        }
        
        // Bonus for entries with metadata (usually more informative)
        if entry.metadata != nil && !entry.metadata!.isEmpty {
            score += 0.1
        }
        
        // Bonus for entries with errors
        if entry.error != nil {
            score += 0.5
            reasons.append(.error(severity: "has_error_info"))
        }
        
        // Context from flows (if part of failed flow, increase relevance)
        if let flows = flows,
           let sessionId = entry.sessionId,
           let relatedFlow = flows.first(where: { $0.sessionId == sessionId }) {
            
            if !relatedFlow.isSuccessful {
                score += 0.3
                reasons.append(.correlation(relatedTo: "failed_flow"))
            }
            
            if relatedFlow.errors.count > 3 {
                score += 0.2
                reasons.append(.correlation(relatedTo: "error_prone_flow"))
            }
        }
        
        // Ensure score is in valid range
        score = max(0.0, min(1.0, score))
        
        return (score, reasons)
    }
    
    // MARK: - Flow Filtering
    
    private func filterFlows(_ flows: [AggregatedLogFlow], config: LogFilterConfig) -> [AggregatedLogFlow] {
        let now = Date()
        
        return flows.filter { flow in
            // Time window
            if let timeWindow = config.timeWindow {
                guard now.timeIntervalSince(flow.startTime) <= timeWindow else { return false }
            }
            
            // Session filter
            if let sessionId = config.sessionId {
                guard flow.sessionId == sessionId else { return false }
            }
            
            // Success filter
            if !config.includeSuccessfulFlows && flow.isSuccessful {
                return false
            }
            
            return true
        }
        .sorted { $0.startTime > $1.startTime } // Most recent first
    }
    
    // MARK: - Summary Generation
    
    private func generateFilterSummary(
        originalCount: Int,
        filteredEntries: [ProductionLogEntry],
        filteredFlows: [AggregatedLogFlow],
        config: LogFilterConfig
    ) -> FilterSummary {
        
        let errorCount = filteredEntries.filter { $0.level == .error || $0.level == .critical }.count
        let warningCount = filteredEntries.filter { $0.level == .warning }.count
        
        let sessionsAffected = Set(filteredEntries.compactMap { $0.sessionId }).count
        
        let timeSpan = filteredEntries.isEmpty ? 0 : 
            filteredEntries.max(by: { $0.timestamp < $1.timestamp })!.timestamp.timeIntervalSince(
                filteredEntries.min(by: { $0.timestamp < $1.timestamp })!.timestamp
            )
        
        // Extract top error types
        let errorTypes = filteredEntries
            .compactMap { $0.error?.type }
            .reduce(into: [String: Int]()) { counts, type in
                counts[type, default: 0] += 1
            }
        let topErrorTypes = Array(errorTypes.sorted { $0.value > $1.value }.prefix(5).map { $0.key })
        
        // Generate recommendations
        let recommendations = generateRecommendations(
            entries: filteredEntries,
            flows: filteredFlows,
            config: config
        )
        
        return FilterSummary(
            entriesShown: filteredEntries.count,
            entriesFiltered: originalCount - filteredEntries.count,
            errorCount: errorCount,
            warningCount: warningCount,
            sessionsAffected: sessionsAffected,
            timeSpan: timeSpan,
            topErrorTypes: topErrorTypes,
            recommendedActions: recommendations
        )
    }
    
    private func generateRecommendations(
        entries: [ProductionLogEntry],
        flows: [AggregatedLogFlow],
        config: LogFilterConfig
    ) -> [String] {
        var recommendations: [String] = []
        
        let errorCount = entries.filter { $0.level >= .error }.count
        let totalCount = entries.count
        
        if totalCount > 0 {
            let errorRate = Double(errorCount) / Double(totalCount)
            
            if errorRate > 0.5 {
                recommendations.append("High error rate detected - focus on top error types first")
            } else if errorRate > 0.2 {
                recommendations.append("Consider investigating recurring error patterns")
            }
        }
        
        // Check for specific patterns in recent entries
        let recentEntries = entries.prefix(20)
        let messages = recentEntries.map { $0.message.lowercased() }
        
        if messages.contains(where: { $0.contains("quota exceeded") }) {
            recommendations.append("API quota issues detected - check rate limiting")
        }
        
        if messages.contains(where: { $0.contains("permission denied") }) {
            recommendations.append("Permission issues detected - verify system permissions")
        }
        
        if messages.contains(where: { $0.contains("network") || $0.contains("timeout") }) {
            recommendations.append("Network connectivity issues detected")
        }
        
        // Flow-based recommendations
        let failedFlows = flows.filter { !$0.isSuccessful }
        if failedFlows.count > flows.count / 2 {
            recommendations.append("Many flows failing - check core functionality")
        }
        
        // If no recommendations yet, provide general advice
        if recommendations.isEmpty && errorCount > 0 {
            recommendations.append("Review error details and stack traces for root cause analysis")
        }
        
        return recommendations
    }
}

// MARK: - Smart Export Formats

extension LogFilter {
    
    /// Export filtered logs in a format optimized for issue reporting
    public func exportForIssueReport(
        entries: [ProductionLogEntry],
        flows: [AggregatedLogFlow],
        issueDescription: String? = nil
    ) -> String {
        
        let config = LogFilterConfig(
            minLevel: .warning,
            includeSuccessfulFlows: false,
            maxEntries: 50,
            relevanceThreshold: 0.4
        )
        
        let filtered = filterLogs(entries: entries, flows: flows, config: config)
        
        var report = """
            Issue Report - TheQuickFox
            =========================
            Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))
            
            """
        
        if let description = issueDescription {
            report += "Issue Description:\n\(description)\n\n"
        }
        
        report += """
            Summary:
            - Total log entries: \(filtered.totalEntriesBeforeFilter)
            - Relevant entries: \(filtered.entries.count)
            - Errors: \(filtered.summary.errorCount)
            - Warnings: \(filtered.summary.warningCount)
            - Sessions affected: \(filtered.summary.sessionsAffected)
            
            """
        
        if !filtered.summary.topErrorTypes.isEmpty {
            report += "Top Error Types:\n"
            for errorType in filtered.summary.topErrorTypes {
                report += "- \(errorType)\n"
            }
            report += "\n"
        }
        
        if !filtered.summary.recommendedActions.isEmpty {
            report += "Recommended Actions:\n"
            for action in filtered.summary.recommendedActions {
                report += "- \(action)\n"
            }
            report += "\n"
        }
        
        report += "Relevant Log Entries:\n"
        report += "=====================\n\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        
        for entry in filtered.entries {
            let sessionTag = entry.sessionId.map { "[\(String($0.uuidString.prefix(8)))]" } ?? "[no-session]"
            report += "[\(formatter.string(from: entry.timestamp))] \(entry.level.emoji) \(entry.category) \(sessionTag)\n"
            report += "   \(entry.message)\n"
            
            if let error = entry.error {
                report += "   Error: \(error.type) - \(error.description)\n"
            }
            
            if let metadata = entry.metadata, !metadata.isEmpty {
                let metadataStr = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                report += "   \(metadataStr)\n"
            }
            
            report += "\n"
        }
        
        return report
    }
}