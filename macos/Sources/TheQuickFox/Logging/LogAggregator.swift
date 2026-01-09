//
//  LogAggregator.swift  
//  TheQuickFox
//
//  Intelligent log aggregation and correlation system.
//  Groups related log events into coherent flows for better debugging.
//

import Foundation

// MARK: - Aggregated Log Flow

public struct AggregatedLogFlow: Codable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let startTime: Date
    public let endTime: Date
    public let trigger: String
    public let outcome: FlowOutcome
    public let phases: [FlowPhase]
    public let errors: [ProductionLogEntry]
    public let summary: FlowSummary
    public let duration: TimeInterval
    
    public var isSuccessful: Bool {
        return outcome == .success && errors.isEmpty
    }
    
    public var hasWarnings: Bool {
        return phases.contains { $0.hasWarnings }
    }
}

public enum FlowOutcome: String, Codable, CaseIterable {
    case success = "success"
    case error = "error"
    case cancelled = "cancelled" 
    case timeout = "timeout"
    case quotaExceeded = "quota_exceeded"
    case permissionDenied = "permission_denied"
    case partial = "partial"
}

public struct FlowPhase: Codable, Identifiable {
    public let id = UUID()
    public let name: PhaseName
    public let startTime: Date
    public let endTime: Date?
    public let entries: [ProductionLogEntry]
    public let status: PhaseStatus
    public let duration: TimeInterval?
    public let metrics: PhaseMetrics?
    
    public var hasWarnings: Bool {
        return entries.contains { $0.level == .warning }
    }
    
    public var hasErrors: Bool {
        return entries.contains { $0.level == .error || $0.level == .critical }
    }
}

public enum PhaseName: String, Codable, CaseIterable {
    case trigger = "trigger"
    case screenshot = "screenshot" 
    case ocr = "ocr"
    case context = "context"
    case prompt = "prompt"
    case aiProcessing = "ai_processing"
    case response = "response"
    case insertion = "insertion"
    case cleanup = "cleanup"
}

public enum PhaseStatus: String, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
    case skipped = "skipped"
}

public struct PhaseMetrics: Codable {
    public let tokenCount: Int?
    public let pixelCount: Int?
    public let dataSize: Int?
    public let retryCount: Int?
    public let accuracy: Double?
}

public struct FlowSummary: Codable {
    public let totalPhases: Int
    public let completedPhases: Int
    public let failedPhases: Int
    public let warningCount: Int
    public let errorCount: Int
    public let bottleneckPhase: String? // Slowest phase
    public let criticalErrors: [String] // High-impact errors
    public let recommendations: [String] // Suggested fixes
}

// MARK: - Log Aggregator

public final class LogAggregator {
    
    public static let shared = LogAggregator()
    
    // MARK: - Configuration
    
    private struct Config {
        static let maxFlowDuration: TimeInterval = 300 // 5 minutes max per flow
        static let phaseTimeout: TimeInterval = 60 // 1 minute per phase max
        static let maxConcurrentFlows = 10
    }
    
    // MARK: - Private State
    
    private let queue = DispatchQueue(label: "LogAggregator")
    private var activeFlows: [UUID: ActiveFlow] = [:]
    private var completedFlows: [AggregatedLogFlow] = []
    private let logger = ProductionLogger.shared
    
    private init() {}
    
    // MARK: - Flow Tracking
    
    /// Process new log entries and correlate them into flows
    public func processLogEntries(_ entries: [ProductionLogEntry]) {
        queue.async { [weak self] in
            self?._processLogEntries(entries)
        }
    }
    
    /// Get recent flows for analysis
    public func getRecentFlows(count: Int = 50) -> [AggregatedLogFlow] {
        queue.sync {
            Array(completedFlows.suffix(count))
        }
    }
    
    /// Get flows with errors for troubleshooting
    public func getErrorFlows(since: Date = Date().addingTimeInterval(-86400)) -> [AggregatedLogFlow] {
        queue.sync {
            completedFlows
                .filter { $0.startTime > since }
                .filter { !$0.isSuccessful }
                .sorted { $0.startTime > $1.startTime }
        }
    }
    
    /// Generate flow analysis report
    public func generateAnalysisReport(since: Date = Date().addingTimeInterval(-86400)) -> FlowAnalysisReport {
        queue.sync {
            let relevantFlows = completedFlows.filter { $0.startTime > since }
            return FlowAnalysisReport(flows: relevantFlows)
        }
    }
    
    // MARK: - Private Processing
    
    private func _processLogEntries(_ entries: [ProductionLogEntry]) {
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            processLogEntry(entry)
        }
        
        // Check for timeouts and complete stalled flows
        timeoutStalledFlows()
        
        // Limit active flows to prevent memory growth
        pruneActiveFlows()
    }
    
    private func processLogEntry(_ entry: ProductionLogEntry) {
        guard let sessionId = entry.sessionId else { return }
        
        // Get or create active flow for this session
        let activeFlow = getOrCreateActiveFlow(for: sessionId, entry: entry)
        
        // Add entry to appropriate phase
        let phaseName = determinePhase(for: entry)
        activeFlow.addEntry(entry, to: phaseName)
        
        // Check if this completes the flow
        if shouldCompleteFlow(activeFlow, entry: entry) {
            completeFlow(activeFlow)
        }
    }
    
    private func getOrCreateActiveFlow(for sessionId: UUID, entry: ProductionLogEntry) -> ActiveFlow {
        if let existing = activeFlows[sessionId] {
            return existing
        }
        
        let flow = ActiveFlow(sessionId: sessionId, startTime: entry.timestamp)
        activeFlows[sessionId] = flow
        return flow
    }
    
    private func determinePhase(for entry: ProductionLogEntry) -> PhaseName {
        let category = entry.category.lowercased()
        let message = entry.message.lowercased()
        
        // Phase detection based on category and message content
        if category.contains("screenshot") || message.contains("screenshot") || message.contains("capture") {
            return .screenshot
        } else if category.contains("ocr") || message.contains("ocr") || message.contains("text recognition") {
            return .ocr  
        } else if category.contains("prompt") || message.contains("prompt") || message.contains("context") {
            if message.contains("building") || message.contains("composing") {
                return .prompt
            } else {
                return .context
            }
        } else if message.contains("pipeline") || message.contains("processing") || message.contains("openai") || message.contains("gemini") {
            if message.contains("response") || message.contains("token") || message.contains("streaming") {
                return .response
            } else {
                return .aiProcessing
            }
        } else if message.contains("insertion") || message.contains("paste") || message.contains("focus") {
            return .insertion
        } else if message.contains("session ended") || message.contains("cleanup") {
            return .cleanup
        } else {
            return .trigger // Default for session start, etc.
        }
    }
    
    private func shouldCompleteFlow(_ activeFlow: ActiveFlow, entry: ProductionLogEntry) -> Bool {
        let message = entry.message.lowercased()
        
        // Complete on explicit session end
        if message.contains("session ended") {
            return true
        }
        
        // Complete on critical errors
        if entry.level == .critical || entry.level == .error {
            if message.contains("pipeline failed") || 
               message.contains("quota exceeded") ||
               message.contains("permission denied") {
                return true
            }
        }
        
        // Complete on successful insertion
        if message.contains("text inserted") || message.contains("insertion successful") {
            return true
        }
        
        // Complete on timeout
        if entry.timestamp.timeIntervalSince(activeFlow.startTime) > Config.maxFlowDuration {
            return true
        }
        
        return false
    }
    
    private func completeFlow(_ activeFlow: ActiveFlow) {
        let aggregatedFlow = activeFlow.finalize()
        completedFlows.append(aggregatedFlow)
        activeFlows.removeValue(forKey: activeFlow.sessionId)
        
        // Log flow completion for monitoring
        logger.logInfo(.generic, "Flow completed", sessionId: aggregatedFlow.sessionId, metadata: [
            "outcome": AnyCodable(aggregatedFlow.outcome.rawValue),
            "duration": AnyCodable(aggregatedFlow.duration),
            "phases": AnyCodable(aggregatedFlow.phases.count),
            "errors": AnyCodable(aggregatedFlow.errors.count)
        ])
    }
    
    private func timeoutStalledFlows() {
        let now = Date()
        let stalledFlows = activeFlows.values.filter { 
            now.timeIntervalSince($0.startTime) > Config.maxFlowDuration
        }
        
        for stalledFlow in stalledFlows {
            stalledFlow.markAsTimedOut()
            completeFlow(stalledFlow)
        }
    }
    
    private func pruneActiveFlows() {
        if activeFlows.count > Config.maxConcurrentFlows {
            // Complete oldest flows first
            let sortedFlows = activeFlows.values.sorted { $0.startTime < $1.startTime }
            let flowsToComplete = Array(sortedFlows.prefix(activeFlows.count - Config.maxConcurrentFlows))
            
            for flow in flowsToComplete {
                completeFlow(flow)
            }
        }
    }
}

// MARK: - Active Flow (Internal Tracking)

private class ActiveFlow {
    let sessionId: UUID
    let startTime: Date
    private var phases: [PhaseName: FlowPhase] = [:]
    private var allEntries: [ProductionLogEntry] = []
    private var timedOut = false
    
    init(sessionId: UUID, startTime: Date) {
        self.sessionId = sessionId
        self.startTime = startTime
    }
    
    func addEntry(_ entry: ProductionLogEntry, to phaseName: PhaseName) {
        allEntries.append(entry)
        
        if phases[phaseName] == nil {
            phases[phaseName] = FlowPhase(
                name: phaseName,
                startTime: entry.timestamp,
                endTime: nil,
                entries: [],
                status: .inProgress,
                duration: nil,
                metrics: nil
            )
        }
        
        // Update phase with new entry
        var phase = phases[phaseName]!
        var entries = phase.entries
        entries.append(entry)
        
        phases[phaseName] = FlowPhase(
            name: phase.name,
            startTime: phase.startTime,
            endTime: entry.timestamp,
            entries: entries,
            status: determinePhaseStatus(entries),
            duration: entry.timestamp.timeIntervalSince(phase.startTime),
            metrics: calculatePhaseMetrics(entries)
        )
    }
    
    func markAsTimedOut() {
        timedOut = true
    }
    
    func finalize() -> AggregatedLogFlow {
        let endTime = allEntries.last?.timestamp ?? Date()
        let errors = allEntries.filter { $0.level == .error || $0.level == .critical }
        let outcome = determineFlowOutcome()
        let sortedPhases = Array(phases.values).sorted { $0.startTime < $1.startTime }
        
        return AggregatedLogFlow(
            id: UUID(),
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime,
            trigger: determineTrigger(),
            outcome: outcome,
            phases: sortedPhases,
            errors: errors,
            summary: generateSummary(phases: sortedPhases, errors: errors),
            duration: endTime.timeIntervalSince(startTime)
        )
    }
    
    private func determinePhaseStatus(_ entries: [ProductionLogEntry]) -> PhaseStatus {
        if entries.contains(where: { $0.level == .error || $0.level == .critical }) {
            return .failed
        } else if entries.contains(where: { $0.message.lowercased().contains("complete") }) {
            return .completed
        } else {
            return .inProgress
        }
    }
    
    private func calculatePhaseMetrics(_ entries: [ProductionLogEntry]) -> PhaseMetrics? {
        var tokenCount: Int?
        var pixelCount: Int?
        var dataSize: Int?
        var retryCount = 0
        
        for entry in entries {
            // Extract metrics from metadata
            if let metadata = entry.metadata {
                if let tokens = metadata["tokens"]?.value as? Int {
                    tokenCount = (tokenCount ?? 0) + tokens
                }
                if let pixels = metadata["pixels"]?.value as? Int {
                    pixelCount = pixels
                }
                if let size = metadata["size"]?.value as? Int {
                    dataSize = (dataSize ?? 0) + size
                }
            }
            
            // Count retries
            if entry.message.lowercased().contains("retry") {
                retryCount += 1
            }
        }
        
        guard tokenCount != nil || pixelCount != nil || dataSize != nil || retryCount > 0 else {
            return nil
        }
        
        return PhaseMetrics(
            tokenCount: tokenCount,
            pixelCount: pixelCount,
            dataSize: dataSize,
            retryCount: retryCount > 0 ? retryCount : nil,
            accuracy: nil
        )
    }
    
    private func determineFlowOutcome() -> FlowOutcome {
        if timedOut {
            return .timeout
        }
        
        let errorEntries = allEntries.filter { $0.level == .error || $0.level == .critical }
        
        for entry in errorEntries {
            let message = entry.message.lowercased()
            if message.contains("quota exceeded") {
                return .quotaExceeded
            } else if message.contains("permission denied") {
                return .permissionDenied
            }
        }
        
        if !errorEntries.isEmpty {
            return .error
        }
        
        // Check for success indicators
        let hasSuccessfulInsertion = allEntries.contains { 
            $0.message.lowercased().contains("text inserted") || 
            $0.message.lowercased().contains("insertion successful")
        }
        
        if hasSuccessfulInsertion {
            return .success
        }
        
        // Check for cancellation
        let wasCancelled = allEntries.contains {
            $0.message.lowercased().contains("cancelled") ||
            $0.message.lowercased().contains("user cancelled")
        }
        
        if wasCancelled {
            return .cancelled
        }
        
        return .partial
    }
    
    private func determineTrigger() -> String {
        // Look for trigger info in early entries
        for entry in allEntries.prefix(3) {
            if let metadata = entry.metadata,
               let trigger = metadata["trigger"]?.value as? String {
                return trigger
            }
        }
        
        return "unknown"
    }
    
    private func generateSummary(phases: [FlowPhase], errors: [ProductionLogEntry]) -> FlowSummary {
        let completedPhases = phases.filter { $0.status == .completed }.count
        let failedPhases = phases.filter { $0.status == .failed }.count
        let warningCount = allEntries.filter { $0.level == .warning }.count
        let errorCount = errors.count
        
        // Find bottleneck (slowest phase)
        let bottleneckPhase = phases
            .compactMap { phase -> (String, TimeInterval)? in
                guard let duration = phase.duration else { return nil }
                return (phase.name.rawValue, duration)
            }
            .max { $0.1 < $1.1 }?.0
        
        // Extract critical errors
        let criticalErrors = errors
            .filter { $0.level == .critical }
            .map { $0.message }
        
        // Generate recommendations
        let recommendations = generateRecommendations(phases: phases, errors: errors)
        
        return FlowSummary(
            totalPhases: phases.count,
            completedPhases: completedPhases,
            failedPhases: failedPhases,
            warningCount: warningCount,
            errorCount: errorCount,
            bottleneckPhase: bottleneckPhase,
            criticalErrors: criticalErrors,
            recommendations: recommendations
        )
    }
    
    private func generateRecommendations(phases: [FlowPhase], errors: [ProductionLogEntry]) -> [String] {
        var recommendations: [String] = []
        
        // Check for common issues and suggest fixes
        for error in errors {
            let message = error.message.lowercased()
            
            if message.contains("quota exceeded") || message.contains("rate limit") {
                recommendations.append("Consider reducing context size or upgrading API plan")
            } else if message.contains("permission denied") {
                recommendations.append("Check system permissions for Accessibility and Screen Recording")
            } else if message.contains("network") || message.contains("timeout") {
                recommendations.append("Check network connection and API endpoint availability")  
            } else if message.contains("ocr failed") {
                recommendations.append("Screenshot may be too complex or low resolution for OCR")
            }
        }
        
        // Check phase durations for bottlenecks
        for phase in phases {
            if let duration = phase.duration, duration > 10.0 {
                if phase.name == .aiProcessing {
                    recommendations.append("AI processing is slow - consider using faster model or reducing context")
                } else if phase.name == .screenshot {
                    recommendations.append("Screenshot capture is slow - check for performance issues")
                }
            }
        }
        
        return Array(Set(recommendations)) // Remove duplicates
    }
}

// MARK: - Flow Analysis Report

public struct FlowAnalysisReport: Codable {
    public let generatedAt: Date
    public let totalFlows: Int
    public let successfulFlows: Int
    public let errorFlows: Int
    public let averageDuration: TimeInterval
    public let commonErrors: [String: Int]
    public let phasePerformance: [String: PhasePerformance]
    public let recommendations: [String]
    
    public init(flows: [AggregatedLogFlow]) {
        self.generatedAt = Date()
        self.totalFlows = flows.count
        self.successfulFlows = flows.filter { $0.isSuccessful }.count
        self.errorFlows = flows.filter { !$0.isSuccessful }.count
        self.averageDuration = flows.isEmpty ? 0 : flows.map { $0.duration }.reduce(0, +) / Double(flows.count)
        
        // Analyze common errors
        var errorCounts: [String: Int] = [:]
        for flow in flows {
            for error in flow.errors {
                let errorType = error.error?.type ?? "Unknown"
                errorCounts[errorType, default: 0] += 1
            }
        }
        self.commonErrors = errorCounts
        
        // Analyze phase performance
        var phaseStats: [String: [TimeInterval]] = [:]
        for flow in flows {
            for phase in flow.phases {
                if let duration = phase.duration {
                    phaseStats[phase.name.rawValue, default: []].append(duration)
                }
            }
        }
        
        self.phasePerformance = phaseStats.mapValues { durations in
            PhasePerformance(
                averageDuration: durations.reduce(0, +) / Double(durations.count),
                maxDuration: durations.max() ?? 0,
                failureRate: 0 // Could calculate from phase status
            )
        }
        
        // Generate global recommendations
        self.recommendations = Self.generateGlobalRecommendations(
            flows: flows,
            commonErrors: errorCounts,
            phasePerformance: phasePerformance
        )
    }
    
    private static func generateGlobalRecommendations(
        flows: [AggregatedLogFlow],
        commonErrors: [String: Int],
        phasePerformance: [String: PhasePerformance]
    ) -> [String] {
        var recommendations: [String] = []
        
        if flows.count > 0 {
            let errorRate = Double(flows.filter { !$0.isSuccessful }.count) / Double(flows.count)
            if errorRate > 0.3 {
                recommendations.append("High error rate detected - consider investigating top error causes")
            }
        }
        
        // Check for slow phases
        for (phaseName, performance) in phasePerformance {
            if performance.averageDuration > 5.0 {
                recommendations.append("\(phaseName) phase is slow (avg \(String(format: "%.1f", performance.averageDuration))s)")
            }
        }
        
        return recommendations
    }
}

public struct PhasePerformance: Codable {
    public let averageDuration: TimeInterval
    public let maxDuration: TimeInterval  
    public let failureRate: Double
}