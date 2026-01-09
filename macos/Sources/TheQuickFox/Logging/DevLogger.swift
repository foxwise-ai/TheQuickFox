//
//  DevLogger.swift
//  TheQuickFox
//
//  Provides lightweight, in-memory logging of LLM interactions when the
//  environment variable `TQF_DEV_LOG` is set (to any value).  Used for
//  debugging prompts, streaming tokens, and final replies without persisting
//  sensitive data to disk.
//
//  To enable:
//      TQF_DEV_LOG=1 swift run TheQuickFox …
//
//  The logger keeps a ring-buffer of the last `maxEntries` requests.
//
//  Access from any thread; internal state is protected by a serial queue.
//

import Foundation

public final class DevLogger {

    // MARK: – Public Types

    public struct Entry: Codable, Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let prompt: String
        public var streamedTokens: [String]
        public var reply: String?

        // Custom init to provide default UUID
        init(
            id: UUID = UUID(), timestamp: Date, prompt: String, streamedTokens: [String],
            reply: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.prompt = prompt
            self.streamedTokens = streamedTokens
            self.reply = reply
        }

        // This makes Codable happy with the immutable `id` that has a default value.
        private enum CodingKeys: String, CodingKey {
            case id, timestamp, prompt, streamedTokens, reply
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.timestamp = try container.decode(Date.self, forKey: .timestamp)
            self.prompt = try container.decode(String.self, forKey: .prompt)
            self.streamedTokens = try container.decode([String].self, forKey: .streamedTokens)
            self.reply = try container.decodeIfPresent(String.self, forKey: .reply)
        }
    }

    // MARK: – Singleton

    public static let shared = DevLogger()

    // MARK: – Private State

    private let isEnabled: Bool
    private let maxEntries = 20
    private var buffer: [Entry] = []
    private let queue = DispatchQueue(label: "TheQuickFox.DevLogger")

    private init() {
        isEnabled = ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil
    }

    // MARK: – Logging API

    /// Begins a new log entry for the given prompt; returns entry ID for updates.
    @discardableResult
    public func start(prompt: String) -> UUID? {
        guard isEnabled else { return nil }
        let entry = Entry(timestamp: Date(), prompt: prompt, streamedTokens: [], reply: nil)
        queue.sync {
            if buffer.count >= maxEntries { buffer.removeFirst() }
            buffer.append(entry)
            print("📝 [DevLog] START \(entry.id) at \(entry.timestamp)")
            // print("🔸 [DevLog] PROMPT:\\n\(prompt)")
        }
        return entry.id
    }

    /// Appends a streamed token to the entry with the given ID.
    public func append(token: String, to id: UUID?) {
        guard isEnabled, let id else { return }
        queue.sync {
            guard let idx = buffer.firstIndex(where: { $0.id == id }) else { return }
            buffer[idx].streamedTokens.append(token)
            // print("🔹 [DevLog] STREAM \\(id) +\\(token.count) chars")
        }
    }

    /// Finalises the entry with the full reply text.
    public func finish(reply: String, for id: UUID?) {
        guard isEnabled, let id else { return }
        queue.sync {
            guard let idx = buffer.firstIndex(where: { $0.id == id }) else { return }
            buffer[idx].reply = reply
            print("✅ [DevLog] FINISH \(id) totalReplyLength=\(reply.count)")
            print("💬 [DevLog] REPLY:\\n\(reply)")
        }
    }

    /// Returns a snapshot of current log entries (oldest → newest).
    public func allEntries() -> [Entry] {
        queue.sync { buffer }
    }
}
