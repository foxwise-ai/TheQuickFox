//
//  ComposeClient.swift
//  TheQuickFox
//
//  Client for the /api/v1/compose endpoint.
//  Sends raw context data to API which builds prompts and streams AI response.
//

import AppKit
import Foundation

public final class ComposeClient {

    // MARK: - Types

    public enum ComposeError: Error, LocalizedError {
        case invalidResponse
        case httpError(status: Int, body: String?)
        case decodingError(Error)
        case apiError(String)
        case cancelled
        case connectionFailed
        case authTokenMissing

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Unable to process server response."
            case .httpError(let status, _):
                if status == 502 || status == 503 || status == 504 {
                    return "Service temporarily unavailable. Please try again later."
                } else if status == 429 {
                    return "Rate limit exceeded. Please wait a moment."
                } else if status == 401 || status == 403 {
                    return "Authentication error. Please restart the app."
                }
                return "Request failed. Please try again."
            case .decodingError:
                return "Unable to process response."
            case .apiError(let msg):
                return msg
            case .cancelled:
                return "Request was cancelled"
            case .connectionFailed:
                return "Unable to connect to TheQuickFox servers."
            case .authTokenMissing:
                return "Authentication failed. Please restart the app."
            }
        }
    }

    // MARK: - Request/Response Types

    private struct ComposeRequest: Encodable {
        let mode: String
        let query: String
        let app_info: AppInfo
        let context_text: String
        let screenshot_base64: String?
        let tone: String?

        struct AppInfo: Encodable {
            let bundle_id: String?
            let app_name: String?
            let window_title: String?
        }
    }

    private struct SSEChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            struct GroundingMetadata: Decodable {
                struct GroundingSupport: Decodable {
                    struct Segment: Decodable {
                        let startIndex: Int?
                        let endIndex: Int
                        let text: String
                    }
                    let segment: Segment
                    let groundingChunkIndices: [Int]?
                }
                struct GroundingChunk: Decodable {
                    struct Web: Decodable {
                        let uri: String
                        let title: String?
                    }
                    let web: Web?
                }
                let groundingSupports: [GroundingSupport]?
                let groundingChunks: [GroundingChunk]?
            }
            let delta: Delta
            let grounding_metadata: GroundingMetadata?
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    // MARK: - Properties

    private let baseURL: String = {
        #if LOCAL_API || DEBUG
        return "http://localhost:4003/api/v1"
        #else
        return "https://api.thequickfox.ai/api/v1"
        #endif
    }()

    private let session: URLSession = URLSession.shared

    // MARK: - Singleton

    public static let shared = ComposeClient()

    private init() {}

    // MARK: - Public API

    /// Stream a compose/ask/code request to the API.
    ///
    /// - Parameters:
    ///   - mode: The mode (compose, ask, code)
    ///   - query: User's terse input
    ///   - appInfo: Active window info
    ///   - contextText: OCR/accessibility extracted text
    ///   - screenshot: Optional screenshot for visual queries
    ///   - tone: Optional tone override
    ///   - onGroundingMetadata: Optional callback for web search grounding data
    /// - Returns: AsyncThrowingStream of incremental content strings
    public func stream(
        mode: HUDMode,
        query: String,
        appInfo: ActiveWindowInfo,
        contextText: String,
        screenshot: NSImage? = nil,
        tone: ResponseTone? = nil,
        onGroundingMetadata: ((GroundingMetadata) -> Void)? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {

        LoggingSystem.shared.logInfo(.pipeline, "Starting compose request", metadata: [
            "mode": AnyCodable(mode.rawValue),
            "has_screenshot": AnyCodable(screenshot != nil),
            "context_length": AnyCodable(contextText.count)
        ])

        // Get auth token
        guard let authToken = try? KeychainManager.shared.getAuthToken() else {
            throw ComposeError.authTokenMissing
        }

        // Build request
        let endpoint = URL(string: "\(baseURL)/compose")!

        // Only include screenshot for Ask mode - Compose/Code modes don't use it on the server
        var screenshotBase64: String? = nil
        if mode == .ask, let screenshot = screenshot {
            screenshotBase64 = convertImageToBase64(screenshot)
        }

        let requestBody = ComposeRequest(
            mode: mode.rawValue,
            query: query,
            app_info: ComposeRequest.AppInfo(
                bundle_id: appInfo.bundleID,
                app_name: appInfo.appName,
                window_title: appInfo.windowTitle
            ),
            context_text: contextText,
            screenshot_base64: screenshotBase64,
            tone: tone?.rawValue
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Capture headers before async call
        let requestHeaders = request.allHTTPHeaderFields ?? [:]

        // Record request in network monitor
        let monitorEntry = await MainActor.run {
            let entry = NetworkMonitor.createComposeEntry(
                url: endpoint,
                headers: requestHeaders,
                body: requestData,
                mode: mode.rawValue
            )
            NetworkMonitor.shared.recordRequest(entry)
            entry.markInProgress()
            return entry
        }

        // Start streaming request
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            LoggingSystem.shared.logError(.pipeline, error, metadata: [
                "context": AnyCodable("compose_connection_failed")
            ])
            await MainActor.run {
                monitorEntry.fail(error: "Connection failed")
            }
            throw ComposeError.connectionFailed
        }

        guard let http = response as? HTTPURLResponse else {
            await MainActor.run {
                monitorEntry.fail(error: "Invalid response")
            }
            throw ComposeError.invalidResponse
        }

        LoggingSystem.shared.logDebug(.pipeline, "Compose HTTP response", metadata: [
            "http_status": AnyCodable(http.statusCode)
        ])

        guard (200..<300).contains(http.statusCode) else {
            let errorBody = try? await bytes.reduce(into: Data()) { $0.append($1) }
            let errorString = errorBody.flatMap { String(data: $0, encoding: .utf8) }
            let error = ComposeError.httpError(status: http.statusCode, body: errorString)

            await MainActor.run {
                var responseHeaders: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    responseHeaders[String(describing: key)] = String(describing: value)
                }
                monitorEntry.complete(
                    statusCode: http.statusCode,
                    responseHeaders: responseHeaders,
                    responseBody: errorBody,
                    responseSummary: "Error: \(errorString?.prefix(100) ?? "Unknown")"
                )
            }

            LoggingSystem.shared.logError(.pipeline, error, metadata: [
                "http_status": AnyCodable(http.statusCode),
                "response_body": AnyCodable(errorString?.prefix(500) ?? "nil")
            ])
            throw error
        }

        // Capture references for use in stream closure
        let httpResponse = http

        // Parse SSE stream
        var iterator = bytes.makeAsyncIterator()

        return AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                var fullResponse = ""

                func processBuffer() {
                    while let range = buffer.range(of: Data("\n\n".utf8)) {
                        let chunkData = buffer.subdata(in: 0..<range.lowerBound)
                        buffer.removeSubrange(0...range.upperBound - 1)
                        if let line = String(data: chunkData, encoding: .utf8) {
                            handleLine(line)
                        }
                    }
                }

                func handleLine(_ line: String) {
                    guard line.hasPrefix("data: ") else { return }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" {
                        LoggingSystem.shared.logInfo(.pipeline, "Compose stream completed")

                        // Complete monitor entry
                        Task { @MainActor in
                            var responseHeaders: [String: String] = [:]
                            for (key, value) in httpResponse.allHeaderFields {
                                responseHeaders[String(describing: key)] = String(describing: value)
                            }
                            let truncatedResponse = fullResponse.prefix(200)
                            monitorEntry.complete(
                                statusCode: httpResponse.statusCode,
                                responseHeaders: responseHeaders,
                                responseBody: fullResponse.data(using: .utf8),
                                responseSummary: "AI response: \"\(truncatedResponse)\(fullResponse.count > 200 ? "..." : "")\""
                            )
                        }

                        continuation.finish()
                        return
                    }

                    guard let data = payload.data(using: .utf8) else { return }

                    do {
                        // Check for error response
                        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = jsonObject["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            LoggingSystem.shared.logError(.pipeline, ComposeError.apiError(message), metadata: [
                                "context": AnyCodable("streaming_api_error")
                            ])

                            Task { @MainActor in
                                monitorEntry.fail(error: "API error: \(message)")
                            }

                            continuation.finish(throwing: ComposeError.apiError(message))
                            return
                        }

                        // Decode streaming chunk
                        let decoded = try JSONDecoder().decode(SSEChunk.self, from: data)
                        let choice = decoded.choices.first
                        let token = choice?.delta.content ?? ""

                        if !token.isEmpty {
                            fullResponse += token
                            continuation.yield(token)
                        }

                        // Handle grounding metadata
                        if let geminiMetadata = choice?.grounding_metadata,
                           let supports = geminiMetadata.groundingSupports,
                           !supports.isEmpty {
                            let publicSupports = supports.map { support in
                                GroundingMetadata.GroundingSupport(
                                    segment: GroundingMetadata.GroundingSupport.Segment(
                                        startIndex: support.segment.startIndex ?? 0,
                                        endIndex: support.segment.endIndex,
                                        text: support.segment.text
                                    ),
                                    groundingChunkIndices: support.groundingChunkIndices ?? []
                                )
                            }

                            let publicChunks = geminiMetadata.groundingChunks?.map { chunk in
                                GroundingMetadata.GroundingChunk(
                                    web: chunk.web.map { web in
                                        GroundingMetadata.GroundingChunk.Web(
                                            uri: web.uri,
                                            title: web.title
                                        )
                                    }
                                )
                            }

                            let metadata = GroundingMetadata(
                                groundingSupports: publicSupports,
                                groundingChunks: publicChunks
                            )
                            onGroundingMetadata?(metadata)
                        }
                    } catch {
                        LoggingSystem.shared.logWarning(.pipeline, "Failed to decode SSE chunk", metadata: [
                            "decode_error": AnyCodable(error.localizedDescription)
                        ])

                        Task { @MainActor in
                            monitorEntry.fail(error: "Decoding error: \(error.localizedDescription)")
                        }

                        continuation.finish(throwing: ComposeError.decodingError(error))
                    }
                }

                do {
                    while let byte = try await iterator.next() {
                        buffer.append(byte)
                        processBuffer()
                    }

                    // Stream ended without [DONE]
                    Task { @MainActor in
                        var responseHeaders: [String: String] = [:]
                        for (key, value) in httpResponse.allHeaderFields {
                            responseHeaders[String(describing: key)] = String(describing: value)
                        }
                        let truncatedResponse = fullResponse.prefix(200)
                        monitorEntry.complete(
                            statusCode: httpResponse.statusCode,
                            responseHeaders: responseHeaders,
                            responseBody: fullResponse.data(using: .utf8),
                            responseSummary: "AI response: \"\(truncatedResponse)\(fullResponse.count > 200 ? "..." : "")\""
                        )
                    }

                    continuation.finish()
                } catch {
                    Task { @MainActor in
                        if (error as? URLError)?.code == .cancelled {
                            monitorEntry.cancel()
                        } else {
                            monitorEntry.fail(error: error.localizedDescription)
                        }
                    }

                    if (error as? URLError)?.code == .cancelled {
                        continuation.finish(throwing: ComposeError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func convertImageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}
