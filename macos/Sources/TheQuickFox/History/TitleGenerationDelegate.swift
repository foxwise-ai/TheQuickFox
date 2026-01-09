//
//  TitleGenerationDelegate.swift
//  TheQuickFox
//
//  Handles LLM title generation callbacks for history entries
//

import Foundation

/// Delegate for handling title generation pipeline callbacks
class TitleGenerationDelegate: PromptPipelineDelegate {
    private let entryId: UUID?
    private let historyManager: HistoryManager
    private let completion: ((String) -> Void)?

    /// Initialize with entry ID for direct history updates
    init(entryId: UUID, historyManager: HistoryManager = HistoryManager.shared) {
        self.entryId = entryId
        self.historyManager = historyManager
        self.completion = nil
    }

    /// Initialize with completion handler for flexible use
    init(completion: @escaping (String) -> Void) {
        self.entryId = nil
        self.historyManager = HistoryManager.shared
        self.completion = completion
    }

    // MARK: - PromptPipelineDelegate

    func pipeline(_ pipeline: PromptPipeline, didReceive token: String) {
        // Don't need to handle partial updates for title generation
    }

    func pipeline(_ pipeline: PromptPipeline, didComplete reply: String) {
        // Extract title from LLM response
        let generatedTitle = extractTitle(from: reply)

        if let entryId = entryId {
            // Direct history update
            historyManager.updateEntryTitle(entryId, title: generatedTitle)
            print("🏷️ Generated title for entry \(entryId): \(generatedTitle)")
        } else if let completion = completion {
            // Call completion handler
            completion(generatedTitle)
            print("🏷️ Generated title: \(generatedTitle)")
        }
    }

    func pipeline(_ pipeline: PromptPipeline, didReceiveGroundingMetadata metadata: GroundingMetadata) {
        // Title generation doesn't use grounding metadata - no-op
    }

    func pipeline(_ pipeline: PromptPipeline, didFail error: Error) {
        print("❌ Failed to generate title for entry \(entryId?.uuidString ?? "unknown"): \(error)")
        // Keep the temporary title if generation fails
    }

    // MARK: - Title Extraction

    /// Extracts clean title from LLM response
    private func extractTitle(from response: String) -> String {
        let cleanTitle = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") // Remove quotes
            .replacingOccurrences(of: "Title: ", with: "") // Remove prefix if present

        // Ensure title isn't too long
        let maxLength = 60
        if cleanTitle.count > maxLength {
            return String(cleanTitle.prefix(maxLength)) + "..."
        }

        return cleanTitle.isEmpty ? "💬 Untitled" : cleanTitle
    }
}
