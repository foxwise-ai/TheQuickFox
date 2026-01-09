//
//  EnhancedContextProvider.swift
//  TheQuickFox
//
//  Combines OCR data from screenshots with accessibility API data to provide
//  comprehensive context including off-screen content, UI relationships, and
//  semantic structure. Includes JSON logging for visualization and debugging.
//

import AppKit
import Foundation
import Vision
import TheQuickFoxCore

// MARK: - Enhanced Context Types

/// Combined context data from OCR, accessibility APIs, and auto-scroll capture
public struct EnhancedContext: Codable {
    public let appInfo: ActiveWindowInfo
    public let ocrData: OCRData
    public let accessibilityData: AccessibilityData
    public let scrollCaptureData: ScrollCaptureData?
    public let captureTimestamp: Date
    public let captureLatencyMs: Double

    public init(
        appInfo: ActiveWindowInfo,
        ocrData: OCRData,
        accessibilityData: AccessibilityData,
        scrollCaptureData: ScrollCaptureData? = nil,
        captureTimestamp: Date = Date(),
        captureLatencyMs: Double
    ) {
        self.appInfo = appInfo
        self.ocrData = ocrData
        self.accessibilityData = accessibilityData
        self.scrollCaptureData = scrollCaptureData
        self.captureTimestamp = captureTimestamp
        self.captureLatencyMs = captureLatencyMs
    }
}

/// OCR data with enhanced structure for visualization
public struct OCRData: Codable {
    public let observations: [[String: Any]]
    public let extractedText: String
    public let latencyMs: Double

    enum CodingKeys: String, CodingKey {
        case observationsJSON, extractedText, latencyMs
    }

    public init(observations: [[String: Any]], extractedText: String, latencyMs: Double) {
        self.observations = observations
        self.extractedText = extractedText
        self.latencyMs = latencyMs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(extractedText, forKey: .extractedText)
        try container.encode(latencyMs, forKey: .latencyMs)

        // Convert observations to JSON string for storage
        let jsonData = try JSONSerialization.data(withJSONObject: observations, options: [])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        try container.encode(jsonString, forKey: .observationsJSON)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        extractedText = try container.decode(String.self, forKey: .extractedText)
        latencyMs = try container.decode(Double.self, forKey: .latencyMs)

        // Decode observations from JSON string
        let jsonString = try container.decode(String.self, forKey: .observationsJSON)
        if let jsonData = jsonString.data(using: .utf8),
           let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
            observations = jsonObject
        } else {
            observations = []
        }
    }

    /// Convert OCR data to TOON format (30-80% smaller than JSON)
    /// Optimized: Direct string generation without Codable overhead
    public func toTOON() throws -> String {
        var output = [String]()

        // Escape text for TOON (handle newlines, quotes)
        let escapedText = extractedText
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

/// Accessibility data with text extraction and UI hierarchy
public struct AccessibilityData: Codable {
    public let roleTree: AXRoleNode?
    public let extractedTexts: [AccessibilityTextElement]
    public let uiElements: [AccessibilityUIElement]
    public let latencyMs: Double
    public let error: String?

    public init(
        roleTree: AXRoleNode?,
        extractedTexts: [AccessibilityTextElement],
        uiElements: [AccessibilityUIElement],
        latencyMs: Double,
        error: String? = nil
    ) {
        self.roleTree = roleTree
        self.extractedTexts = extractedTexts
        self.uiElements = uiElements
        self.latencyMs = latencyMs
        self.error = error
    }
}

/// Text element extracted from accessibility APIs
public struct AccessibilityTextElement: Codable {
    public let text: String
    public let role: String
    public let position: CGRect?
    public let isVisible: Bool
    public let attributes: [String: String]

    enum CodingKeys: String, CodingKey {
        case text, role, position, isVisible, attributes
    }

    public init(text: String, role: String, position: CGRect?, isVisible: Bool, attributes: [String: String] = [:]) {
        self.text = text
        self.role = role
        self.position = position
        self.isVisible = isVisible
        self.attributes = attributes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(role, forKey: .role)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(attributes, forKey: .attributes)

        // Encode CGRect as dictionary
        if let pos = position {
            let posDict = [
                "x": pos.origin.x,
                "y": pos.origin.y,
                "width": pos.size.width,
                "height": pos.size.height
            ]
            try container.encode(posDict, forKey: .position)
        } else {
            try container.encodeNil(forKey: .position)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        role = try container.decode(String.self, forKey: .role)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        attributes = try container.decode([String: String].self, forKey: .attributes)

        // Decode CGRect from dictionary
        if let posDict = try container.decodeIfPresent([String: Double].self, forKey: .position) {
            position = CGRect(
                x: posDict["x"] ?? 0,
                y: posDict["y"] ?? 0,
                width: posDict["width"] ?? 0,
                height: posDict["height"] ?? 0
            )
        } else {
            position = nil
        }
    }
}

/// Scroll capture data for visualization
public struct ScrollCaptureData: Codable {
    public let frameCount: Int
    public let combinedText: String
    public let captureLatencyMs: Double
    public let totalCharacters: Int
    public let config: String // JSON string of config
    public let frames: [ScrollFrameData]

    public init(from result: ScrollCaptureResult) {
        self.frameCount = result.frameCount
        self.combinedText = result.combinedText
        self.captureLatencyMs = result.totalLatencyMs
        self.totalCharacters = result.totalCharacters

        // Encode config as JSON string
        if let configData = try? JSONEncoder().encode(result.config),
           let configString = String(data: configData, encoding: .utf8) {
            self.config = configString
        } else {
            self.config = "{}"
        }

        // Convert frames (limit to avoid massive JSON)
        self.frames = Array(result.frames.prefix(5)).map { ScrollFrameData(from: $0) }
    }
}

/// Individual scroll frame data (lightweight for JSON)
public struct ScrollFrameData: Codable {
    public let index: Int
    public let newTextLength: Int
    public let cumulativeTextLength: Int
    public let scrollPosition: CGPoint
    public let timestamp: Date

    public init(from frame: ScrollFrame) {
        self.index = frame.index
        self.newTextLength = frame.newTextFound.count
        self.cumulativeTextLength = frame.cumulativeText.count
        self.scrollPosition = frame.scrollPosition
        self.timestamp = frame.captureTimestamp
    }
}

/// UI element from accessibility APIs
public struct AccessibilityUIElement: Codable {
    public let role: String
    public let title: String?
    public let value: String?
    public let position: CGRect?
    public let isVisible: Bool
    public let children: Int

    enum CodingKeys: String, CodingKey {
        case role, title, value, position, isVisible, children
    }

    public init(role: String, title: String?, value: String?, position: CGRect?, isVisible: Bool, children: Int) {
        self.role = role
        self.title = title
        self.value = value
        self.position = position
        self.isVisible = isVisible
        self.children = children
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(children, forKey: .children)

        // Encode CGRect as dictionary
        if let pos = position {
            let posDict = [
                "x": pos.origin.x,
                "y": pos.origin.y,
                "width": pos.size.width,
                "height": pos.size.height
            ]
            try container.encode(posDict, forKey: .position)
        } else {
            try container.encodeNil(forKey: .position)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        children = try container.decode(Int.self, forKey: .children)

        // Decode CGRect from dictionary
        if let posDict = try container.decodeIfPresent([String: Double].self, forKey: .position) {
            position = CGRect(
                x: posDict["x"] ?? 0,
                y: posDict["y"] ?? 0,
                width: posDict["width"] ?? 0,
                height: posDict["height"] ?? 0
            )
        } else {
            position = nil
        }
    }
}

// MARK: - Enhanced Context Provider

public enum EnhancedContextProvider {

    /// Captures comprehensive context combining OCR, accessibility, and scroll capture data
    public static func capture(
        from screenshot: WindowScreenshot,
        includeAccessibility: Bool = true,
        maxAccessibilityDepth: Int = 5,
        // enableScrollCapture: Bool = false,
        scrollConfig: ScrollCaptureConfig = .conservative
    ) async throws -> EnhancedContext {

        let startTime = DispatchTime.now()

        // 1. Extract OCR data
        let ocrResult = try TextRecognizer.recognize(img: screenshot.image)
        let ocrData = OCRData(
            observations: ocrResult.observations,
            extractedText: ocrResult.texts,
            latencyMs: ocrResult.latencyMs
        )

        // 2. Extract accessibility data
        let accessibilityData: AccessibilityData
        if includeAccessibility {
            accessibilityData = await extractAccessibilityData(
                from: screenshot.activeInfo,
                maxDepth: maxAccessibilityDepth
            )
        } else {
            accessibilityData = AccessibilityData(
                roleTree: nil,
                extractedTexts: [],
                uiElements: [],
                latencyMs: 0,
                error: "Accessibility extraction disabled"
            )
        }

        // // 3. Perform scroll capture if enabled
        // let scrollCaptureData: ScrollCaptureData?
        // if enableScrollCapture {
        //     do {
        //         let scrollResult = try await ScrollCaptureManager.captureWithAutoScroll(config: scrollConfig)
        //         scrollCaptureData = ScrollCaptureData(from: scrollResult)

        //         // Use scroll capture text if we got more content
        //         if scrollResult.combinedText.count > ocrData.extractedText.count * 2 {
        //             print("ScrollCapture: Got \(scrollResult.combinedText.count) chars vs OCR \(ocrData.extractedText.count) chars")
        //         }
        //     } catch {
        //         print("ScrollCapture failed: \(error)")
        //         scrollCaptureData = nil
        //     }
        // } else {
        //     scrollCaptureData = nil
        // }

        let endTime = DispatchTime.now()
        let totalLatency = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        let context = EnhancedContext(
            appInfo: screenshot.activeInfo,
            ocrData: ocrData,
            accessibilityData: accessibilityData,
            // scrollCaptureData: scrollCaptureData,
            captureLatencyMs: totalLatency
        )

        // 3. Log context for visualization if dev logging is enabled
        if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
            try logContextForVisualization(context)
        }

        return context
    }

    // MARK: - Private Helpers

    private static func extractAccessibilityData(
        from appInfo: ActiveWindowInfo,
        maxDepth: Int
    ) async -> AccessibilityData {

        let startTime = DispatchTime.now()

        do {
            // Use existing ApplicationContextProvider to get role tree
            let (_, roleTree) = try ApplicationContextProvider.fetch(
                includeRoleTree: true,
                maxDepth: maxDepth
            )

            // Extract additional text and UI elements
            let (textElements, uiElements) = try await extractDetailedAccessibilityInfo(for: appInfo)

            let endTime = DispatchTime.now()
            let latency = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

            return AccessibilityData(
                roleTree: roleTree,
                extractedTexts: textElements,
                uiElements: uiElements,
                latencyMs: latency
            )

        } catch {
            let endTime = DispatchTime.now()
            let latency = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

            return AccessibilityData(
                roleTree: nil,
                extractedTexts: [],
                uiElements: [],
                latencyMs: latency,
                error: error.localizedDescription
            )
        }
    }

    private static func extractDetailedAccessibilityInfo(
        for appInfo: ActiveWindowInfo
    ) async throws -> ([AccessibilityTextElement], [AccessibilityUIElement]) {

        guard let runningApp = NSRunningApplication(processIdentifier: appInfo.pid) else {
            return ([], [])
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)

        // Get focused window
        var focusedWindow: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard focusErr == .success, let windowElement = focusedWindow else {
            return ([], [])
        }

        // Recursively extract text and UI elements
        var textElements: [AccessibilityTextElement] = []
        var uiElements: [AccessibilityUIElement] = []

        try extractElementsRecursively(
            from: windowElement as! AXUIElement,
            textElements: &textElements,
            uiElements: &uiElements,
            depth: 0,
            maxDepth: 8
        )

        return (textElements, uiElements)
    }

    private static func extractElementsRecursively(
        from element: AXUIElement,
        textElements: inout [AccessibilityTextElement],
        uiElements: inout [AccessibilityUIElement],
        depth: Int,
        maxDepth: Int
    ) throws {

        if depth > maxDepth { return }

        let role = fetchRole(for: element)
        let title = fetchTitle(for: element)
        let value = fetchValue(for: element)
        let position = fetchPosition(for: element)

        // Extract text content
        if let textValue = value, !textValue.isEmpty {
            let textElement = AccessibilityTextElement(
                text: textValue,
                role: role,
                position: position,
                isVisible: isElementVisible(element, position: position),
                attributes: extractAttributes(for: element)
            )
            textElements.append(textElement)
        }

        // Extract UI element info
        let childCount = getChildrenCount(for: element)
        let uiElement = AccessibilityUIElement(
            role: role,
            title: title,
            value: value,
            position: position,
            isVisible: isElementVisible(element, position: position),
            children: childCount
        )
        uiElements.append(uiElement)

        // Recurse into children
        var childrenValue: AnyObject?
        let childrenErr = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        if childrenErr == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                try extractElementsRecursively(
                    from: child,
                    textElements: &textElements,
                    uiElements: &uiElements,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
            }
        }
    }

    // MARK: - Accessibility Helpers

    private static func fetchRole(for element: AXUIElement) -> String {
        var roleValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        return (err == .success) ? (roleValue as? String ?? "<unknown>") : "<unknown>"
    }

    private static func fetchTitle(for element: AXUIElement) -> String? {
        var titleValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        return (err == .success) ? (titleValue as? String) : nil
    }

    private static func fetchValue(for element: AXUIElement) -> String? {
        var valueObj: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
        return (err == .success) ? (valueObj as? String) : nil
    }

    private static func fetchPosition(for element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard posErr == .success, let posValue = positionValue,
              sizeErr == .success, let szValue = sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(szValue as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    private static func isElementVisible(_ element: AXUIElement, position: CGRect?) -> Bool {
        // Simple heuristic: element is visible if it has a valid position and size
        guard let pos = position else { return false }
        return pos.width > 0 && pos.height > 0
    }

    private static func extractAttributes(for element: AXUIElement) -> [String: String] {
        var attributes: [String: String] = [:]

        // Get common attributes
        let attributesToCheck = [
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXRoleDescriptionAttribute
        ]

        for attribute in attributesToCheck {
            var value: AnyObject?
            let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if err == .success, let stringValue = value as? String {
                attributes[String(attribute)] = stringValue
            }
        }

        return attributes
    }

    private static func getChildrenCount(for element: AXUIElement) -> Int {
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if err == .success, let children = childrenValue as? [AXUIElement] {
            return children.count
        }
        return 0
    }

    // MARK: - Logging and Visualization

    private static func logContextForVisualization(_ context: EnhancedContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(context)

        // Save to temporary file for visualization
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TheQuickFox-Context-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        print("Enhanced Context Data:")
        print("======================")
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
        print("\nContext saved to: \(tempURL.path)")
        print("Open this file with the context visualizer for detailed analysis.")
    }
}
