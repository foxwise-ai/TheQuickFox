import Foundation

/// Represents a single query-response interaction in the history
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let query: String
    let response: String
    let mode: HUDMode
    let tone: ResponseTone
    
    /// LLM-generated title with emoji (e.g., "🌙 Intercom response to Kevin")
    var title: String
    
    /// Temporary title used before LLM generation completes
    var isTemporaryTitle: Bool
    
    init(
        query: String,
        response: String,
        mode: HUDMode,
        tone: ResponseTone,
        title: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.response = response.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mode = mode
        self.tone = tone
        
        // Use provided title or create temporary one
        if let title = title {
            self.title = title
            self.isTemporaryTitle = false
        } else {
            // Fallback temporary title while waiting for LLM
            let truncatedQuery = String(query.prefix(30))
            self.title = "💬 \(truncatedQuery)\(query.count > 30 ? "..." : "")"
            self.isTemporaryTitle = true
        }
    }
    
    /// Update the title with LLM-generated version
    mutating func updateTitle(_ newTitle: String) {
        self.title = newTitle
        self.isTemporaryTitle = false
    }
    
    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    /// Short preview of the query for display
    var queryPreview: String {
        let maxLength = 100
        if query.count <= maxLength {
            return query
        }
        return String(query.prefix(maxLength)) + "..."
    }
    
    /// Short preview of the response for display
    var responsePreview: String {
        let maxLength = 200
        if response.count <= maxLength {
            return response
        }
        return String(response.prefix(maxLength)) + "..."
    }
}

// MARK: - Extensions for existing types to support Codable

extension HUDMode: Codable {}
extension ResponseTone: Codable {}