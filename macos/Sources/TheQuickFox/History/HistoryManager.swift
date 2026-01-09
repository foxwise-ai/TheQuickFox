import Foundation
import Combine

/// Manages query-response history with persistent storage
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileManager = FileManager.default
    private let historyFileName = "history.json"

    /// URL to the history file in Application Support
    private var historyFileURL: URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        let tqfURL = appSupportURL.appendingPathComponent("TheQuickFox")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: tqfURL,
                                       withIntermediateDirectories: true)

        return tqfURL.appendingPathComponent(historyFileName)
    }

    private init() {
        loadHistory()
    }

    /// Add a new history entry
    func addEntry(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0) // Insert at beginning (most recent first)
        saveHistory()

        print("📚 Added history entry: \(entry.title)")
    }

    /// Update an existing entry (used for title updates)
    func updateEntry(_ entryId: UUID, with updatedEntry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else {
            print("❌ Could not find entry to update: \(entryId)")
            return
        }

        entries[index] = updatedEntry
        saveHistory()

        print("✏️ Updated history entry title: \(updatedEntry.title)")
    }

    /// Update title for a specific entry
    func updateEntryTitle(_ entryId: UUID, title: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else {
            print("❌ Could not find entry to update title: \(entryId)")
            return
        }

        entries[index].updateTitle(title)
        saveHistory()

        print("🏷️ Updated entry title: \(title)")
    }

    /// Remove an entry
    func removeEntry(_ entryId: UUID) {
        entries.removeAll { $0.id == entryId }
        saveHistory()

        print("🗑️ Removed history entry: \(entryId)")
    }

    /// Clear all history
    func clearHistory() {
        entries.removeAll()
        saveHistory()

        print("🧹 Cleared all history")
    }

    /// Get entries for a specific mode
    func entries(for mode: HUDMode) -> [HistoryEntry] {
        return entries.filter { $0.mode == mode }
    }

    /// Get recent entries (last N entries)
    func recentEntries(count: Int = 10) -> [HistoryEntry] {
        return Array(entries.prefix(count))
    }

    // MARK: - Persistence

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let data = try encoder.encode(entries)
            try data.write(to: historyFileURL)

            print("💾 Saved \(entries.count) history entries")
        } catch {
            print("❌ Failed to save history: \(error)")
        }
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            print("📚 No existing history file found")
            return
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            entries = try decoder.decode([HistoryEntry].self, from: data)

            print("📚 Loaded \(entries.count) history entries")
        } catch {
            print("❌ Failed to load history: \(error)")
            // Don't crash - just start with empty history
            entries = []
        }
    }

    // MARK: - Statistics

    var totalEntries: Int {
        entries.count
    }

    var responseEntries: Int {
        entries.filter { $0.mode == .compose }.count
    }

    var askEntries: Int {
        entries.filter { $0.mode == .ask }.count
    }

    /// Get history statistics
    func getStatistics() -> (total: Int, respond: Int, ask: Int, oldestDate: Date?) {
        return (
            total: totalEntries,
            respond: responseEntries,
            ask: askEntries,
            oldestDate: entries.last?.timestamp
        )
    }
}
