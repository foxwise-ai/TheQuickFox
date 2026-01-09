//
//  ScrollCaptureManager.swift
//  TheQuickFox
//
//  Auto-scrolling screenshot capture system that can capture content beyond
//  the visible viewport by automatically scrolling through scrollable areas
//  and combining OCR results from multiple frames.
//

import AppKit
import Foundation
import TheQuickFoxCore

// MARK: - Scroll Capture Types

/// Configuration for scroll capture behavior
public struct ScrollCaptureConfig: Codable {
    /// Maximum number of scroll steps to take
    public let maxScrollSteps: Int
    /// Percentage of viewport height to scroll each step (0.0-1.0)
    public let scrollStepPercent: Double
    /// Delay between scroll actions (seconds)
    public let scrollDelay: TimeInterval
    /// Delay after scroll before screenshot (seconds)
    public let settleDelay: TimeInterval
    /// Minimum new text required to continue scrolling
    public let minNewTextThreshold: Int
    /// Maximum total capture time (seconds)
    public let maxCaptureTime: TimeInterval

    public static let `default` = ScrollCaptureConfig(
        maxScrollSteps: 10,
        scrollStepPercent: 0.7, // 70% overlap between frames
        scrollDelay: 0.1,
        settleDelay: 0.2,
        minNewTextThreshold: 50, // chars
        maxCaptureTime: 15.0
    )

    public static let conservative = ScrollCaptureConfig(
        maxScrollSteps: 5,
        scrollStepPercent: 0.8,
        scrollDelay: 0.05,
        settleDelay: 0.4,
        minNewTextThreshold: 20, // Lower threshold to capture more content
        maxCaptureTime: 10.0
    )

    public static let aggressive = ScrollCaptureConfig(
        maxScrollSteps: 20,
        scrollStepPercent: 0.8,
        scrollDelay: 0.05,
        settleDelay: 0.1,
        minNewTextThreshold: 20,
        maxCaptureTime: 25.0
    )
}

/// Result of scroll capture operation
public struct ScrollCaptureResult {
    public let frames: [ScrollFrame]
    public let combinedText: String
    public let totalLatencyMs: Double
    public let originalScrollPosition: CGPoint
    public let config: ScrollCaptureConfig

    public var frameCount: Int { frames.count }
    public var totalCharacters: Int { combinedText.count }
}

/// Individual frame captured during scrolling
public struct ScrollFrame {
    public let index: Int
    public let screenshot: WindowScreenshot
    public let ocrResult: TextRecognizer.Result
    public let scrollPosition: CGPoint
    public let estimatedScrollDistance: CGFloat
    public let newTextFound: String
    public let cumulativeText: String
    public let captureTimestamp: Date
}

/// Scroll capture errors
public enum ScrollCaptureError: Error, LocalizedError {
    case noScrollAreaFound
    case scrollOperationFailed
    case captureTimeout
    case accessibilityDenied

    public var errorDescription: String? {
        switch self {
        case .noScrollAreaFound:
            return "No scrollable area found in the active window"
        case .scrollOperationFailed:
            return "Failed to perform scroll operation"
        case .captureTimeout:
            return "Scroll capture exceeded maximum time limit"
        case .accessibilityDenied:
            return "Accessibility permission required for scroll capture"
        }
    }
}

// MARK: - Scroll Capture Manager

public enum ScrollCaptureManager {

    /// Performs auto-scroll capture on the active window
    public static func captureWithAutoScroll(
        // config: ScrollCaptureConfig = .default
        config: ScrollCaptureConfig = .aggressive
    ) async throws -> ScrollCaptureResult {

        let startTime = DispatchTime.now()

        // 1. Get the active application and window
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            throw ScrollCaptureError.noScrollAreaFound
        }

        // 2. Find scrollable areas in the active window
        let scrollInfo = try findScrollableArea(for: activeApp)

        // 3. Get initial scroll position (to restore later)
        let originalPosition = getScrollPosition(for: scrollInfo.scrollElement) ?? CGPoint.zero

        // 4. Always scroll to top first to capture complete document
        print("ScrollCapture: Original position: \(originalPosition), scrolling to top first")
        await performSyntheticScrollToTop()

        // 5. Capture phase: collect all screenshots first
        var frames: [ScrollFrame] = []

        let initialScreenshot = try await captureCurrentWindow(showHighlight: false)
        print("ScrollCapture: Starting capture phase from TOP")

        // Store initial frame with placeholder OCR
        let placeholderOCR = TextRecognizer.Result(observations: [], texts: "", latencyMs: 0.0)
        let initialFrame = ScrollFrame(
            index: 0,
            screenshot: initialScreenshot,
            ocrResult: placeholderOCR,
            scrollPosition: originalPosition,
            estimatedScrollDistance: 0,
            newTextFound: "",
            cumulativeText: "",
            captureTimestamp: Date()
        )

        frames.append(initialFrame)

        // 6. Perform scrolling capture
        var currentStep = 1
        // var lastNewTextCount = initialOCR.texts.count // Unused for now

        while currentStep < config.maxScrollSteps {

            // Check timeout
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000.0
            if elapsed > config.maxCaptureTime {
                throw ScrollCaptureError.captureTimeout
            }

            // Perform scroll with app-specific distance
            let scrollDistance = calculateScrollDistance(
                for: scrollInfo.scrollArea,
                stepPercent: config.scrollStepPercent,
                appInfo: initialScreenshot.activeInfo
            )

            let scrollSuccess = try await performScroll(
                element: scrollInfo.scrollElement,
                distance: scrollDistance,
                delay: config.scrollDelay
            )

            if !scrollSuccess {
                break // Reached end of scrollable content
            }

            // Capture new frame (no OCR yet - just collect screenshots)
            let screenshot = try await captureCurrentWindow(showHighlight: false)
            let currentScrollPos = getScrollPosition(for: scrollInfo.scrollElement) ?? CGPoint.zero

            print("ScrollCapture: Got scroll offset from scroll bars: \(currentScrollPos)")

            // Check if we've reached the bottom based on scroll position
            // For normalized scroll values: if we're at 0.95+ we're essentially at the bottom
            let isAtBottom = currentScrollPos.y >= 0.95
            let scrollPositionUnchanged = (frames.last?.scrollPosition.y ?? -1) == currentScrollPos.y

            if isAtBottom || scrollPositionUnchanged {
                print("ScrollCapture: Reached bottom (position: \(currentScrollPos.y), unchanged: \(scrollPositionUnchanged))")
                // Still capture this final frame before breaking
                let placeholderOCR = TextRecognizer.Result(observations: [], texts: "", latencyMs: 0.0)
                let frame = ScrollFrame(
                    index: currentStep,
                    screenshot: screenshot,
                    ocrResult: placeholderOCR,
                    scrollPosition: currentScrollPos,
                    estimatedScrollDistance: scrollDistance,
                    newTextFound: "",
                    cumulativeText: "",
                    captureTimestamp: Date()
                )
                frames.append(frame)
                break
            }

            // Store frame with placeholder OCR for now
            let placeholderOCR = TextRecognizer.Result(observations: [], texts: "", latencyMs: 0.0)
            let frame = ScrollFrame(
                index: currentStep,
                screenshot: screenshot,
                ocrResult: placeholderOCR,
                scrollPosition: currentScrollPos,
                estimatedScrollDistance: scrollDistance,
                newTextFound: "",
                cumulativeText: "",
                captureTimestamp: Date()
            )
            frames.append(frame)

            print("ScrollCapture: Step \(currentStep), scroll position: \(currentScrollPos.y)")

            // Continue to next scroll step (no early termination based on OCR)

            currentStep += 1
            // lastNewTextCount = newText.count // Unused for now
        }

        // 7. Restore original scroll position
        try await restoreScrollPosition(
            element: scrollInfo.scrollElement,
            to: originalPosition
        )

        print("ScrollCapture: Successfully restored via scroll bars")

        // 8. OCR Processing Phase - process all captured frames
        print("ScrollCapture: Starting OCR phase for \(frames.count) frames")
        var processedFrames: [ScrollFrame] = []
        var cumulativeText = ""

        for (_, frame) in frames.enumerated() {
            let ocrResult = try TextRecognizer.recognize(img: frame.screenshot.image)
            let newText = extractNewText(from: ocrResult.texts, compared: cumulativeText)
            cumulativeText = combineText(existing: cumulativeText, new: newText)

            let processedFrame = ScrollFrame(
                index: frame.index,
                screenshot: frame.screenshot,
                ocrResult: ocrResult,
                scrollPosition: frame.scrollPosition,
                estimatedScrollDistance: frame.estimatedScrollDistance,
                newTextFound: newText,
                cumulativeText: cumulativeText,
                captureTimestamp: frame.captureTimestamp
            )
            processedFrames.append(processedFrame)

            print("ScrollCapture: Step \(frame.index), new text: \(newText.count) chars, total: \(cumulativeText.count) chars")
        }

        let endTime = DispatchTime.now()
        let totalLatency = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        print("ScrollCapture: Got \(cumulativeText.count) chars vs OCR \(processedFrames.first?.ocrResult.texts.count ?? 0) chars")

        return ScrollCaptureResult(
            frames: processedFrames,
            combinedText: cumulativeText,
            totalLatencyMs: totalLatency,
            originalScrollPosition: originalPosition,
            config: config
        )
    }

    // MARK: - Private Helpers

    private struct ScrollableAreaInfo {
        let scrollElement: AXUIElement
        let scrollArea: CGRect
        let canScrollVertically: Bool
        let canScrollHorizontally: Bool
    }

    private static func findScrollableArea(for app: NSRunningApplication) throws -> ScrollableAreaInfo {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get focused window
        var focusedWindow: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard focusErr == .success, let windowElement = focusedWindow else {
            if focusErr == .apiDisabled {
                throw ScrollCaptureError.accessibilityDenied
            }
            throw ScrollCaptureError.noScrollAreaFound
        }

        // Find scrollable elements
        if let scrollInfo = findScrollableElementRecursively(windowElement as! AXUIElement) {
            return scrollInfo
        }

        throw ScrollCaptureError.noScrollAreaFound
    }

    private static func findScrollableElementRecursively(_ element: AXUIElement) -> ScrollableAreaInfo? {
        // Check if current element is scrollable
        if let scrollInfo = checkIfScrollable(element) {
            return scrollInfo
        }

        // Check children
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if err == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let scrollInfo = findScrollableElementRecursively(child) {
                    return scrollInfo
                }
            }
        }

        return nil
    }

    private static func checkIfScrollable(_ element: AXUIElement) -> ScrollableAreaInfo? {
        // Get role
        var roleValue: AnyObject?
        let roleErr = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        guard roleErr == .success, let role = roleValue as? String else { return nil }

        // Check if it's a scrollable role
        guard role == kAXScrollAreaRole as String || role == kAXListRole as String ||
              role == kAXTableRole as String else {
            return nil
        }

        // Get position and size
        guard let rect = getElementRect(element) else { return nil }

        // Check if element has scroll bars or scroll attributes
        let canScrollV = hasScrollCapability(element, orientation: .vertical)
        let canScrollH = hasScrollCapability(element, orientation: .horizontal)

        if canScrollV || canScrollH {
            return ScrollableAreaInfo(
                scrollElement: element,
                scrollArea: rect,
                canScrollVertically: canScrollV,
                canScrollHorizontally: canScrollH
            )
        }

        return nil
    }

    private enum ScrollOrientation {
        case vertical, horizontal
    }

    private static func hasScrollCapability(_ element: AXUIElement, orientation: ScrollOrientation) -> Bool {
        // Check for scroll bars
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if err == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                var roleValue: AnyObject?
                let roleErr = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
                if roleErr == .success, let role = roleValue as? String, role == kAXScrollBarRole as String {
                    // Check scroll bar orientation
                    var orientationValue: AnyObject?
                    let orientationErr = AXUIElementCopyAttributeValue(child, kAXOrientationAttribute as CFString, &orientationValue)
                    if orientationErr == .success, let orientationStr = orientationValue as? String {
                        let isVertical = orientationStr == "AXVerticalOrientation"
                        let isHorizontal = orientationStr == "AXHorizontalOrientation"

                        if (orientation == .vertical && isVertical) ||
                           (orientation == .horizontal && isHorizontal) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    private static func getElementRect(_ element: AXUIElement) -> CGRect? {
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

    private static func getScrollPosition(for element: AXUIElement) -> CGPoint? {
        // Method 1: Try to get scroll position via scroll bars
        if let scrollOffset = getScrollOffsetFromScrollBars(element) {
            print("ScrollCapture: Got scroll offset from scroll bars: \(scrollOffset)")
            return scrollOffset
        }

        // Method 2: Try various scroll-related attributes
        let scrollAttributes = [
            "AXVerticalScrollBar",
            "AXHorizontalScrollBar",
            kAXValueAttribute as String,
            "AXScrollPosition"
        ]

        for attribute in scrollAttributes {
            var scrollValue: AnyObject?
            let scrollErr = AXUIElementCopyAttributeValue(element, attribute as CFString, &scrollValue)

            if scrollErr == .success, let value = scrollValue {
                if CFGetTypeID(value) == AXValueGetTypeID() {
                    var point = CGPoint.zero
                    AXValueGetValue(value as! AXValue, .cgPoint, &point)
                    if point != CGPoint.zero {
                        print("ScrollCapture: Got scroll position via \(attribute): \(point)")
                        return point
                    }
                }
            }
        }

        // Method 3: Fallback - use document bounds if available
        if let docBounds = getDocumentBounds(element) {
            print("ScrollCapture: Using document bounds as fallback: \(docBounds)")
            return docBounds.origin
        }

        print("ScrollCapture: No reliable scroll position found, using zero")
        return CGPoint.zero
    }

    private static func getScrollOffsetFromScrollBars(_ element: AXUIElement) -> CGPoint? {
        var scrollOffset = CGPoint.zero
        var foundOffset = false

        // Find scroll bars in children
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if err == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                var roleValue: AnyObject?
                let roleErr = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)

                if roleErr == .success, let role = roleValue as? String, role == kAXScrollBarRole as String {
                    // Check scroll bar orientation and value
                    var orientationValue: AnyObject?
                    var valueObj: AnyObject?

                    let orientationErr = AXUIElementCopyAttributeValue(child, kAXOrientationAttribute as CFString, &orientationValue)
                    let valueErr = AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueObj)

                    if orientationErr == .success, valueErr == .success,
                       let orientationStr = orientationValue as? String,
                       let value = valueObj as? NSNumber {

                        let scrollValue = CGFloat(value.doubleValue)

                        if orientationStr == "AXVerticalOrientation" {
                            scrollOffset.y = scrollValue
                            foundOffset = true
                        } else if orientationStr == "AXHorizontalOrientation" {
                            scrollOffset.x = scrollValue
                            foundOffset = true
                        }
                    }
                }
            }
        }

        return foundOffset ? scrollOffset : nil
    }

    private static func getDocumentBounds(_ element: AXUIElement) -> CGRect? {
        // Try to get document or content bounds
        let boundsAttributes = [
            "AXContents",
            "AXDocument",
            "AXVisibleCharacterRange"
        ]

        for attribute in boundsAttributes {
            var value: AnyObject?
            let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if err == .success {
                // Found some content attribute
                return CGRect(x: 0, y: 0, width: 100, height: 100) // Placeholder
            }
        }

        return nil
    }

    private static func calculateScrollDistance(for scrollArea: CGRect, stepPercent: Double, appInfo: ActiveWindowInfo) -> CGFloat {
        let baseDistance = scrollArea.height * CGFloat(stepPercent)

        // App-specific scroll distance adjustments
        guard let bundleID = appInfo.bundleID?.lowercased() else {
            return baseDistance
        }

        switch bundleID {
        case let id where id.contains("preview"):
            // PDFs in Preview need larger scrolls
            let pdfScrollMultiplier: CGFloat = 2.5
            print("ScrollCapture: Using PDF scroll multiplier (\(pdfScrollMultiplier)x) for Preview")
            return baseDistance * pdfScrollMultiplier

        case let id where id.contains("safari"), let id where id.contains("chrome"), let id where id.contains("firefox"), let id where id.contains("arc"):
            // Web browsers - normal scroll distance
            return baseDistance

        case let id where id.contains("textedit"), let id where id.contains("pages"), let id where id.contains("word"):
            // Document editors - larger scrolls
            return baseDistance * 1.5

        default:
            return baseDistance
        }
    }

    private static func performScroll(
        element: AXUIElement,
        distance: CGFloat,
        delay: TimeInterval
    ) async throws -> Bool {

        // Method 1: Try scroll action
        if let scrollAction = findScrollAction(for: element) {
            let result = AXUIElementPerformAction(element, scrollAction as CFString)
            if result == .success {
                return true
            }
        }

        // Method 2: Try synthetic scroll events
        return performSyntheticScroll(distance: distance, delay: delay)
    }

    private static func findScrollAction(for element: AXUIElement) -> String? {
        var actionsValue: CFArray?
        let err = AXUIElementCopyActionNames(element, &actionsValue)

        if err == .success, let actions = actionsValue as? [String] {
            // Look for scroll actions
            for action in actions {
                if action.contains("Scroll") {
                    return action
                }
            }
        }

        return nil
    }

    private static func performSyntheticScroll(distance: CGFloat, delay: TimeInterval) -> Bool {
        // Get mouse location
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let flippedY = screenFrame.height - mouseLocation.y

        // Break large scrolls into smaller, smoother steps
        let maxScrollPerEvent: CGFloat = 200
        let scrollSteps = max(1, Int(distance / maxScrollPerEvent))
        let scrollPerStep = distance / CGFloat(scrollSteps)

        for i in 0..<scrollSteps {
            // Create scroll event with momentum-style easing
            let progress = CGFloat(i) / CGFloat(scrollSteps)
            let easedDistance = scrollPerStep * (1.0 - progress * 0.3) // Gradually reduce scroll speed

            guard let scrollEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(-easedDistance/8), // Smaller divisor for smoother scroll
                wheel2: 0,
                wheel3: 0
            ) else {
                continue
            }

            scrollEvent.location = CGPoint(x: mouseLocation.x, y: flippedY)
            scrollEvent.post(tap: .cghidEventTap)

        }

        return true
    }

    private static func restoreScrollPosition(
        element: AXUIElement,
        to position: CGPoint
    ) async throws {
        print("ScrollCapture: Restoring to position \(position)")

        // Method 1: Try to restore via scroll bars
        if await restoreViaScrollBars(element: element, to: position) {
            print("ScrollCapture: Successfully restored via scroll bars")
            return
        }

        // Method 2: Try direct AX attribute setting
        var mutablePosition = position
        let targetValue = AXValueCreate(.cgPoint, &mutablePosition)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, targetValue!)

        if result == AXError.success {
            // Wait for restore to complete
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            print("ScrollCapture: Successfully restored via AX attribute")
            return
        }

        print("ScrollCapture: AX restore failed (\(result)), trying synthetic scroll")

        // Method 3: Synthetic scrolling restoration
        // First, scroll to top using scroll events
        await performSyntheticScrollToTop()

        // If we need to scroll down from top, do it gradually
        if position.y > 10 {
            print("ScrollCapture: Scrolling down to restore position y=\(position.y)")
            let totalDistance = position.y
            let scrollSteps = max(3, Int(totalDistance / 200)) // More steps for larger distances
            let scrollPerStep = totalDistance / CGFloat(scrollSteps)

            for step in 0..<scrollSteps {
                let _ = performSyntheticScroll(distance: scrollPerStep, delay: 0.03)
                print("ScrollCapture: Restoration step \(step + 1)/\(scrollSteps)")
            }
        }

        print("ScrollCapture: Restoration attempt completed")
    }

    private static func restoreViaScrollBars(element: AXUIElement, to position: CGPoint) async -> Bool {
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        guard err == .success, let children = childrenValue as? [AXUIElement] else {
            return false
        }

        var restored = false

        for child in children {
            var roleValue: AnyObject?
            let roleErr = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)

            if roleErr == .success, let role = roleValue as? String, role == kAXScrollBarRole as String {
                // Check scroll bar orientation
                var orientationValue: AnyObject?
                let orientationErr = AXUIElementCopyAttributeValue(child, kAXOrientationAttribute as CFString, &orientationValue)

                if orientationErr == .success, let orientationStr = orientationValue as? String {
                    let targetValue: CGFloat

                    if orientationStr == "AXVerticalOrientation" {
                        targetValue = position.y
                    } else if orientationStr == "AXHorizontalOrientation" {
                        targetValue = position.x
                    } else {
                        continue
                    }

                    // Set the scroll bar value
                    let valueNumber = NSNumber(value: Double(targetValue))
                    let result = AXUIElementSetAttributeValue(child, kAXValueAttribute as CFString, valueNumber)

                    if result == .success {
                        restored = true
                    }
                }
            }
        }

        return restored
    }

    private static func performSyntheticScrollToTop() async {
        print("ScrollCapture: Scrolling to top with scroll events only")

        // Skip keyboard shortcuts that cause system sounds - use pure scrolling instead
        // Send many scroll up events to ensure we reach absolute top
        print("ScrollCapture: Sending scroll up events to reach top")

        // Phase 1: Large scroll ups to get to top quickly
        for _ in 0..<20 {
            performSyntheticScrollUp(distance: 2000)
        }

        // Phase 2: Smaller scroll ups to ensure we're at absolute top
        for _ in 0..<10 {
            performSyntheticScrollUp(distance: 500)
        }

        // Phase 3: Tiny scroll ups to handle any remaining offset
        for _ in 0..<5 {
            performSyntheticScrollUp(distance: 100)
        }

        print("ScrollCapture: Completed scroll to top sequence (scroll events only)")
    }

    private static func performSyntheticScrollUp(distance: CGFloat) {
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let flippedY = screenFrame.height - mouseLocation.y

        // Create more reliable scroll event with proper parameters
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line, // Use line units for more consistent behavior
            wheelCount: 1,
            wheel1: Int32(distance/20), // Positive for up scroll, adjusted divisor
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        scrollEvent.location = CGPoint(x: mouseLocation.x, y: flippedY)
        // Add small momentum flag for smoother scrolling
        scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        scrollEvent.post(tap: .cghidEventTap)
    }

    private static func captureCurrentWindow(showHighlight: Bool = false) async throws -> WindowScreenshot {
        return try await withCheckedThrowingContinuation { continuation in
            ScreenshotManager.shared.requestCapture { result in
                switch result {
                case .success(let screenshot):
                    continuation.resume(returning: screenshot)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func extractNewText(from newText: String, compared existingText: String) -> String {
        // Simple approach: find text that's not in existing text
        let newLines = newText.components(separatedBy: .newlines)
        let existingLines = Set(existingText.components(separatedBy: .newlines))

        let uniqueLines = newLines.filter { line in
            !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !existingLines.contains(line)
        }

        return uniqueLines.joined(separator: "\n")
    }

    private static func combineText(existing: String, new: String) -> String {
        if existing.isEmpty {
            return new
        }

        if new.isEmpty {
            return existing
        }

        return existing + "\n\n--- SCROLL FRAME ---\n\n" + new
    }
}
