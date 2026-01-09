import AppKit
import Vision

public enum OCRError: Error {
    case conversionFailed
    case noTextFound
}

/// Simple on-device OCR helper.
public enum TextRecognizer {

    /// Result of text recognition.
    public struct Result {
        public let observations: [[String: Any]]
        public let texts: String
        public let latencyMs: Double

        public init(observations: [[String: Any]], texts: String, latencyMs: Double) {
            self.observations = observations
            self.texts = texts
            self.latencyMs = latencyMs
        }
    }

    static func getSupportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        do {
            return try request.supportedRecognitionLanguages()
        } catch {
            return ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
        }
    }

    static var revision: Int {
        // The deployment target is modern enough that we can
        // safely assume the latest revision is available.
        return VNRecognizeTextRequestRevision3
    }

    /// Perform synchronous OCR on an `NSImage`.
    ///
    /// - Parameters:
    ///   - img: Source bitmap (ideally cropped to content area).
    /// - Returns: `Result` containing unique strings and latency.
    /// - Throws: Any `Vision` or image-conversion errors.
    public static func recognize(
        img: NSImage
    ) throws -> Result {

        let startTime = DispatchTime.now()

        guard let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.conversionFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = getSupportedLanguages()
        request.revision = revision
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            throw OCRError.noTextFound
        }

        var positionalJson: [[String: Any]] = []
        var fullText: [String] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            fullText.append(candidate.string)
            extractSubBounds(
                imageRef: cgImage, observation: observation, recognizedText: candidate,
                positionalJson: &positionalJson)
        }

        let combinedFullText = fullText.joined(separator: "\n")
        let endTime = DispatchTime.now()
        let latencyMs =
            Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        return Result(observations: positionalJson, texts: combinedFullText, latencyMs: latencyMs)
    }

    static func extractSubBounds(
        imageRef: CGImage, observation: VNRecognizedTextObservation,
        recognizedText: VNRecognizedText, positionalJson: inout [[String: Any]]
    ) {
        func normalizeCoordinate(_ value: CGFloat) -> CGFloat {
            return max(0, min(1, value))
        }

        let text = recognizedText.string
        let topLeft = observation.topLeft
        let topRight = observation.topRight
        let bottomRight = observation.bottomRight
        let bottomLeft = observation.bottomLeft

        let quad: [String: Any] = [
            "topLeft": [
                "x": normalizeCoordinate(topLeft.x),
                "y": normalizeCoordinate(1 - topLeft.y),
            ],
            "topRight": [
                "x": normalizeCoordinate(topRight.x),
                "y": normalizeCoordinate(1 - topRight.y),
            ],
            "bottomRight": [
                "x": normalizeCoordinate(bottomRight.x),
                "y": normalizeCoordinate(1 - bottomRight.y),
            ],
            "bottomLeft": [
                "x": normalizeCoordinate(bottomLeft.x),
                "y": normalizeCoordinate(1 - bottomLeft.y),
            ],
        ]

        positionalJson.append([
            "text": text,
            "confidence": observation.confidence,
            "quad": quad,
        ])
    }
}

// MARK: - JSON Output for Logging
extension TextRecognizer.Result: CustomStringConvertible {
    public var description: String {
        // Convert observations to JSON format for better logging
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            // Fallback to original format if JSON serialization fails
            return "Result(observations: \(observations), texts: \"\(texts)\", latencyMs: \(latencyMs))"
        }
        return "Result(observations: [], texts: \"\(texts)\", latencyMs: \(latencyMs))"
    }
}

// MARK: - TOON Output for Token-Efficient LLM Context
extension TextRecognizer.Result {
    /// Convert OCR result to TOON format (30-80% smaller than JSON)
    /// Optimized: Direct string generation without Codable overhead
    public func toTOON() throws -> String {
        var output = [String]()

        // Escape text for TOON (handle newlines, quotes)
        let escapedText = texts
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        output.append("text: \"\(escapedText)\"")
        output.append("latencyMs: \(String(format: "%.2f", latencyMs))")

        // Tabular format for observations: more compact than list format
        output.append("observations[\(observations.count)]{text,confidence,x,y,width,height}:")

        for obs in observations {
            let text = obs["text"] as? String ?? ""
            let confidence = obs["confidence"] as? Double ?? 0
            let quad = obs["quad"] as? [String: Any] ?? [:]
            let topLeft = quad["topLeft"] as? [String: Double] ?? [:]
            let bottomRight = quad["bottomRight"] as? [String: Double] ?? [:]

            let x = topLeft["x"] ?? 0
            let y = topLeft["y"] ?? 0
            let width = (bottomRight["x"] ?? 0) - x
            let height = (bottomRight["y"] ?? 0) - y

            // Escape text field
            let escapedObsText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: "\n", with: "\\n")

            // Format: text,confidence,x,y,width,height
            let row = "  \"\(escapedObsText)\",\(String(format: "%.2f", confidence)),\(String(format: "%.4f", x)),\(String(format: "%.4f", y)),\(String(format: "%.4f", width)),\(String(format: "%.4f", height))"
            output.append(row)
        }

        return output.joined(separator: "\n")
    }
}
