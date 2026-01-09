//
//  ServiceProtocols.swift
//  TheQuickFox
//
//  Protocol definitions for external services used by effects
//

import Foundation

// MARK: - Result Type (for compatibility)

enum ServiceResult<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}

// MARK: - Screenshot Service

protocol ScreenshotService {
    func captureActiveWindow(completion: @escaping (ServiceResult<WindowScreenshot, Error>) -> Void)
}

// MARK: - Pipeline Service

protocol PipelineService {
    func startProcessing(
        query: String,
        mode: HUDMode,
        tone: ResponseTone,
        screenshot: WindowScreenshot?,
        isDemoMode: Bool,
        callback: @escaping (PipelineResult) -> Void
    )
}

enum PipelineResult {
    case token(String)
    case completion(String)
    case groundingMetadata(GroundingMetadata)
    case error(Error)
}

// MARK: - Focus Service

protocol FocusService {
    func captureCurrentFocus() -> Bool
    func insertTextAndRestoreFocus(_ text: String, completion: @escaping (InsertionFailureReason?) -> Void)
}

// MARK: - Window Service

protocol WindowService {
    func showHUD(skipScreenshot: Bool)
    func hideHUD()
    func setHUDVisible(_ visible: Bool)
    func getCurrentHUDFrame() -> NSRect?
}

// MARK: - History Service

protocol HistoryService {
    func saveEntry(_ entry: HistoryEntry)
    func deleteEntry(_ id: UUID)
    func clearAll()
    func loadEntries() -> [HistoryEntry]
    func updateEntryTitle(_ id: UUID, title: String)
}

// MARK: - Default Implementations (Bridges to existing code)

final class DefaultScreenshotService: ScreenshotService {
    func captureActiveWindow(completion: @escaping (ServiceResult<WindowScreenshot, Error>) -> Void) {
        ScreenshotManager.shared.requestCapture { result in
            switch result {
            case .success(let screenshot):
                completion(.success(screenshot))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

final class DefaultPipelineService: PipelineService {
    private var currentPipeline: PromptPipeline?
    private var currentDelegate: PipelineServiceDelegate?

    func startProcessing(
        query: String,
        mode: HUDMode,
        tone: ResponseTone,
        screenshot: WindowScreenshot?,
        isDemoMode: Bool,
        callback: @escaping (PipelineResult) -> Void
    ) {
        do {
            let delegate = PipelineServiceDelegate(callback: callback)
            currentDelegate = delegate  // Retain the delegate

            print("🚀 PipelineService.startProcessing - screenshot: \(screenshot != nil)")
            if let screenshot = screenshot {
                print("🚀 Screenshot passed to pipeline - app: \(screenshot.activeInfo.appName ?? "nil"), size: \(screenshot.image.size)")
            }

            let pipeline = try PromptPipeline(
                userDraft: query,
                openAiApiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
                geminiApiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
                anthropicApiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
                delegate: delegate,
                cachedScreenshot: screenshot,
                mode: mode,
                tone: mode == .compose ? tone : nil,
                autoInsertText: false,
                isDemoMode: isDemoMode
            )

            currentPipeline = pipeline
            pipeline.start()

        } catch {
            callback(.error(error))
        }
    }
}

private class PipelineServiceDelegate: PromptPipelineDelegate {
    private let callback: (PipelineResult) -> Void

    init(callback: @escaping (PipelineResult) -> Void) {
        self.callback = callback
    }

    func pipeline(_ pipeline: PromptPipeline, didReceive token: String) {
        callback(.token(token))
    }

    func pipeline(_ pipeline: PromptPipeline, didComplete reply: String) {
        callback(.completion(reply))
    }

    func pipeline(_ pipeline: PromptPipeline, didReceiveGroundingMetadata metadata: GroundingMetadata) {
        callback(.groundingMetadata(metadata))
    }

    func pipeline(_ pipeline: PromptPipeline, didFail error: Error) {
        callback(.error(error))
    }
}

final class DefaultFocusService: FocusService {
    func captureCurrentFocus() -> Bool {
        do {
            return try FocusManager.shared.captureCurrentFocus()
        } catch {
            print("DEBUG: Failed to capture focus: \(error)")
            return false
        }
    }

    func insertTextAndRestoreFocus(_ text: String, completion: @escaping (InsertionFailureReason?) -> Void) {
        let failureReason = FocusManager.shared.insertReplyAndRestoreFocus(text)
        completion(failureReason)
    }
}

final class DefaultWindowService: WindowService {
    func showHUD(skipScreenshot: Bool) {
        Task { @MainActor in
            HUDManager.shared.showHUD(skipScreenshot: skipScreenshot)
        }
    }

    func hideHUD() {
        Task { @MainActor in
            HUDManager.shared.hideHUD()
        }
    }

    func setHUDVisible(_ visible: Bool) {
        Task { @MainActor in
            HUDManager.shared.setHUDVisible(visible)
        }
    }

    func getCurrentHUDFrame() -> NSRect? {
        return MainActor.assumeIsolated {
            HUDManager.shared.getCurrentWindowFrame()
        }
    }
}

final class DefaultHistoryService: HistoryService {
    func saveEntry(_ entry: HistoryEntry) {
        HistoryManager.shared.addEntry(entry)
    }

    func deleteEntry(_ id: UUID) {
        // HistoryManager would need to be updated to support deletion by ID
        // For now, this is a no-op
    }

    func clearAll() {
        // HistoryManager would need to be updated to support clearing
        // For now, this is a no-op
    }

    func loadEntries() -> [HistoryEntry] {
        return HistoryManager.shared.entries
    }

    func updateEntryTitle(_ id: UUID, title: String) {
        HistoryManager.shared.updateEntryTitle(id, title: title)
    }
}
