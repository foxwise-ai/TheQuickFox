//
//  ScreenshotManager.swift
//  TheQuickFox
//
//  Coordinates asynchronous, debounced screenshot capture requests.
//  Ensures only one capture runs at a time, delivers the same result to
//  multiple callers, and caches the most recent shot for rapid re-invocation.
//
//  Usage:
//      ScreenshotManager.shared.requestCapture { result in
//          switch result {
//          case .success(let shot):  /* use shot.image / shot.activeInfo */
//          case .failure(let error): /* handle error */
//          }
//      }
//
//  Thread-safe via a private serial dispatch queue.
//

import Foundation
import AppKit

public final class ScreenshotManager {

    // MARK: – Types


    // MARK: – Singleton

    public static let shared = ScreenshotManager()
    private init() {}

    // MARK: – Properties

    /// Serial queue guarding mutable state.
    private let stateQueue = DispatchQueue(label: "com.foxwiseai.thequickfox.screenshotmanager.state")

    /// Indicates whether a capture operation is currently running.
    private var isCapturing = false

    /// Pending completion handlers awaiting the current capture.
    private var pending: [ (Swift.Result<WindowScreenshot, Error>) -> Void ] = []


    // MARK: – Public API

    /// Queues a screenshot capture. Multiple concurrent calls are coalesced.
    ///
    /// - Parameter completion: Called on the main queue with the capture result.
    public func requestCapture(completion: @escaping (Swift.Result<WindowScreenshot, Error>) -> Void) {
        stateQueue.async {
            // Append to pending list.
            self.pending.append(completion)

            // If a capture is already in progress, nothing more to do.
            guard !self.isCapturing else { return }
            self.isCapturing = true

            // Perform capture on a background queue to avoid UI jank.
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Swift.Result<WindowScreenshot, Error>
                do {
                    let shot = try WindowScreenshotter.captureFrontmost()
                    result = .success(shot)
                } catch {
                    result = .failure(error)
                }

                // Deliver result to all pending handlers.
                self.stateQueue.async {
                    let handlers = self.pending
                    self.pending.removeAll()
                    self.isCapturing = false
                    DispatchQueue.main.async {
                        handlers.forEach { $0(result) }
                    }
                }
            }
        }
    }

    // MARK: – Synchronous Helper (optional)

    /// Performs a synchronous capture on the calling thread. Primarily useful
    /// for unit tests. Throws on error.
    public func captureSync() throws -> WindowScreenshot {
        let semaphore = DispatchSemaphore(value: 0)
        var output: Swift.Result<WindowScreenshot, Error>!

        requestCapture { result in
            output = result
            semaphore.signal()
        }
        semaphore.wait()
        return try output.get()
    }

    /// Async/await convenience wrapper around `requestCapture`.
    /// - Returns: A `WindowScreenshot` result.
    @available(macOS 12.0, *)
    public func capture() async throws -> WindowScreenshot {
        try await withCheckedThrowingContinuation { cont in
            requestCapture { result in
                cont.resume(with: result)
            }
        }
    }
}
