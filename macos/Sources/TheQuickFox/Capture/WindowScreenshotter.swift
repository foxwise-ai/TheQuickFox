//
//  WindowScreenshotter.swift
//  TheQuickFox
//
//  Utility for grabbing an `NSImage` of the currently-active (frontmost)
//  application window. Uses the CoreGraphics window list to find the top-most
//  on-screen window, captures it at full (retina-aware) resolution, and returns
//  the bitmap plus a latency measurement.
//
//  The capture avoids window shadows/frames by specifying
//  `kCGWindowImageBoundsIgnoreFraming`.
//
//  NOTE: Requires the executable to have Screen Recording permission on macOS
//  10.15+ (System Settings ▸ Privacy & Security ▸ Screen Recording).
//

import Cocoa
import CoreGraphics
import os

/// Lightweight metadata describing the currently-active window / application.
/// Down-stream tasks (4+) can use this instead of parsing raw CoreGraphics
/// dictionaries.
public struct ActiveWindowInfo: Codable {
    /// Bundle identifier of the owning application (e.g. "com.apple.Mail")
    public let bundleID: String?
    /// Human-readable application name (e.g. "Mail")
    public let appName: String?
    /// The window title if available (e.g. the subject line of an email)
    public let windowTitle: String?
    /// PID of the owning process
    public let pid: pid_t
}

public struct WindowScreenshot {
    let image: NSImage
    /// Duration of the capture operation in milliseconds.
    let latencyMs: Double
    /// Normalised metadata about the active window / app.
    /// This is what Task 4 will consume for context extraction.
    let activeInfo: ActiveWindowInfo
    /// Raw CoreGraphics window dictionary (optional – useful for debugging).
    let windowInfo: [String: Any]?
    /// URLs of saved scroll view screenshots
    let scrollViewScreenshots: [URL]
}

/// Errors that can occur during capture.
public enum WindowScreenshotError: Error {
    case frontmostWindowNotFound
    case captureFailed
}

enum WindowScreenshotter {
    /// Captures the frontmost on-screen window.
    ///
    /// - Returns: `WindowScreenshot` containing the bitmap and latency.
    /// - Throws: `WindowScreenshotError` if capture fails.
    static func captureFrontmost() throws -> WindowScreenshot {
        let start = CFAbsoluteTimeGetCurrent()

        // Step 1: Retrieve window list ordered from front to back and determine the
        // primary "content" window (layer-0, decent size) for the frontmost app.
        guard
            let infoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            throw WindowScreenshotError.frontmostWindowNotFound
        }

        // Find the first window that is NOT TheQuickFox's own window
        guard let frontMost = infoList.first(where: { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerApp = NSRunningApplication(processIdentifier: pid),
                  let bundleID = ownerApp.bundleIdentifier else {
                return true // If we can't determine the bundle ID, include it
            }
            return !bundleID.contains("TheQuickFox")
        }) else {
            throw WindowScreenshotError.frontmostWindowNotFound
        }

        // Heuristic: pick the first window that belongs to the same PID, lives on
        // layer 0 (regular content), and is larger than 100×100 px. If nothing
        // matches, fall back to the frontmost non-TheQuickFox window.

        // Get the frontmost application, but exclude TheQuickFox
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let workspacePID: pid_t?
        if let app = frontmostApp,
           let bundleID = app.bundleIdentifier,
           !bundleID.contains("TheQuickFox") {
            workspacePID = app.processIdentifier
            LoggingManager.shared.info(.screenshot, "Using frontmost app: \(app.localizedName ?? "Unknown") (bundle: \(bundleID))")
        } else {
            workspacePID = nil
            let frontmostName = frontmostApp?.localizedName ?? "Unknown"
            let frontmostBundle = frontmostApp?.bundleIdentifier ?? "Unknown"
            LoggingManager.shared.info(.screenshot, "Skipping frontmost app \(frontmostName) (bundle: \(frontmostBundle)) - using fallback")
        }

        let targetPID = workspacePID ?? (frontMost[kCGWindowOwnerPID as String] as? pid_t)

        // Double-check that we're not targeting TheQuickFox even in fallback
        if let pid = targetPID,
           let targetApp = NSRunningApplication(processIdentifier: pid),
           let bundleID = targetApp.bundleIdentifier,
           bundleID.contains("TheQuickFox") {
            LoggingManager.shared.error(.screenshot, "Fallback would target TheQuickFox - finding alternative")
            throw WindowScreenshotError.frontmostWindowNotFound
        }


        func findScrollViews(for app: NSRunningApplication) -> [URL] {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
            guard result == .success, let windows = value as? [AXUIElement] else { return [] }

            var savedScreenshots: [URL] = []
            for window in windows {
                print("window.title")
                let screenshots = findScrollViewsInElement(window)
                savedScreenshots.append(contentsOf: screenshots)
            }
            return savedScreenshots
        }

        func findScrollViewsInElement(_ element: AXUIElement) -> [URL] {
            var savedScreenshots: [URL] = []
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                let childrenArray = children as? [AXUIElement] {
                for child in childrenArray {
                    var role: AnyObject?
                    if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                        let roleStr = role as? String, roleStr == kAXScrollAreaRole as String {
                        print("Found scroll view: \(child)")

                        // Get position and size
                        var positionValue: AnyObject?
                        var sizeValue: AnyObject?

                        if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &positionValue) == .success,
                           let posValue = positionValue as! AXValue?,
                           AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeValue) == .success,
                           let szValue = sizeValue as! AXValue? {

                            var position = CGPoint.zero
                            var size = CGSize.zero

                            AXValueGetValue(posValue, .cgPoint, &position)
                            AXValueGetValue(szValue, .cgSize, &size)

                            print("Position: \(position), Size: \(size)")

                            // Capture screenshot of the scroll view area
                            let rect = CGRect(origin: position, size: size)
                            if let screenshot = captureRect(rect) {
                                // Only save to file in debug mode
                                if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
                                    // Save to file
                                    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                                    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                                    let filename = "ScrollView-\(timestamp)-\(rect.origin.x)-\(rect.origin.y).png"
                                    let fileURL = tempDir.appendingPathComponent(filename)

                                    if let tiff = screenshot.tiffRepresentation,
                                       let bitmap = NSBitmapImageRep(data: tiff),
                                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                                        do {
                                            try pngData.write(to: fileURL, options: .atomic)
                                            savedScreenshots.append(fileURL)
                                            print("Saved scroll view screenshot to: \(fileURL.path)")
                                        } catch {
                                            print("Failed to save screenshot: \(error)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Recursively search children
                    let childScreenshots = findScrollViewsInElement(child)
                    savedScreenshots.append(contentsOf: childScreenshots)
                }
            }
            return savedScreenshots
        }




        // Capture screenshots of scroll views and save them
        var scrollViewScreenshots: [URL] = []
        if let runningApp = NSRunningApplication(processIdentifier: targetPID!) {
            scrollViewScreenshots = findScrollViews(for: runningApp)
        }

        // Helper function to capture a specific rect on screen
        func captureRect(_ rect: CGRect) -> NSImage? {
            guard let cgImage = CGWindowListCreateImage(
                rect,
                [.optionOnScreenOnly],
                kCGNullWindowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: .zero)
        }

        // Debug: Log first 10 windows and specifically look for target app windows
        if ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil {
            LoggingManager.shared.info(.screenshot, "Top 10 windows in list:")
            for (index, info) in infoList.prefix(10).enumerated() {
                let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
                let layer = info[kCGWindowLayer as String] as? Int ?? -1
                let bounds = info[kCGWindowBounds as String] as? [String: Any]
                let w = bounds?["Width"] as? CGFloat ?? 0
                let h = bounds?["Height"] as? CGFloat ?? 0
                let windowName = info[kCGWindowName as String] as? String ?? "Untitled"
                let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
                let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 0
                LoggingManager.shared.info(.screenshot, "  \(index + 1). \(ownerName) - '\(windowName)' (PID: \(pid), Layer: \(layer), Size: \(Int(w))x\(Int(h)), Alpha: \(String(format: "%.2f", alpha)))")
            }

            // Debug: Look specifically for all windows from the target app
            if let targetPID = targetPID {
                let targetAppWindows = infoList.filter { info in
                    (info[kCGWindowOwnerPID as String] as? pid_t) == targetPID
                }
                LoggingManager.shared.info(.screenshot, "Found \(targetAppWindows.count) windows from target app (PID: \(targetPID)):")
                for (index, info) in targetAppWindows.enumerated() {
                    let layer = info[kCGWindowLayer as String] as? Int ?? -1
                    let bounds = info[kCGWindowBounds as String] as? [String: Any]
                    let w = bounds?["Width"] as? CGFloat ?? 0
                    let h = bounds?["Height"] as? CGFloat ?? 0
                    let windowName = info[kCGWindowName as String] as? String ?? "Untitled"
                    let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 0
                    LoggingManager.shared.info(.screenshot, "    \(index + 1). '\(windowName)' (Layer: \(layer), Size: \(Int(w))x\(Int(h)), Alpha: \(String(format: "%.2f", alpha)))")
                }
            }
        }

        let candidateInfo = WindowSelector.findBestWindow(
            targetPID: targetPID!,
            windowList: infoList,
            fallback: frontMost
        )!

        guard let windowID = candidateInfo[kCGWindowNumber as String] as? CGWindowID else {
            throw WindowScreenshotError.frontmostWindowNotFound
        }

        // Step 2: Capture image for that window ID.
        guard
            let cgImage = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw WindowScreenshotError.captureFailed
        }

        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        let end = CFAbsoluteTimeGetCurrent()

        // Dev logging of screenshot metrics
        let pxW = cgImage.width
        let pxH = cgImage.height
        LoggingManager.shared.info(.screenshot, "Screenshot captured: \(pxW)x\(pxH) px in \(String(format: "%.1f", (end - start) * 1000)) ms")

        // Create ActiveWindowInfo from the same candidateInfo that provided the windowID
        let actualPID = candidateInfo[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let actualApp = NSRunningApplication(processIdentifier: actualPID)
        LoggingManager.shared.info(.screenshot, "Screenshot window: \(actualApp?.localizedName ?? "Unknown") (PID: \(actualPID), Bundle: \(actualApp?.bundleIdentifier ?? "Unknown"))")

        return WindowScreenshot(
            image: nsImage,
            latencyMs: (end - start) * 1000,
            activeInfo: ActiveWindowInfo(
                bundleID: NSRunningApplication(processIdentifier: actualPID)?.bundleIdentifier,
                appName: NSRunningApplication(processIdentifier: actualPID)?.localizedName,
                windowTitle: candidateInfo[kCGWindowName as String] as? String,
                pid: actualPID
            ),
            windowInfo: candidateInfo,
            scrollViewScreenshots: scrollViewScreenshots
        )
    }

    /// Returns all screenshot URLs from a WindowScreenshot, including the main window
    /// and any scroll view captures.
    ///
    /// - Parameter shot: The `WindowScreenshot` containing the captures.
    /// - Parameter mainURL: The URL of the main window screenshot (if saved).
    /// - Returns: Array of all screenshot URLs.
    static func getAllScreenshotURLs(from shot: WindowScreenshot, mainURL: URL? = nil) -> [URL] {
        var urls: [URL] = []
        if let main = mainURL {
            urls.append(main)
        }
        urls.append(contentsOf: shot.scrollViewScreenshots)
        return urls
    }

    /// Saves a captured screenshot to a PNG file inside the system temporary
    /// directory and returns the file URL.  Useful for manual testing.
    ///
    /// - Parameter shot: The `WindowScreenshot` to persist.
    /// - Throws: Propagates I/O errors or `captureFailed` if PNG encoding fails.
    /// - Returns: Location of the written PNG file.
    static func saveToTemporary(_ shot: WindowScreenshot,
                                prefix: String = "TheQuickFoxCapture") throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = tempDir.appendingPathComponent("\(prefix)-\(timestamp).png")

        guard
            let tiff = shot.image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw WindowScreenshotError.captureFailed
        }

        try pngData.write(to: url, options: .atomic)

        // Log scroll view screenshots if any were captured
        if !shot.scrollViewScreenshots.isEmpty {
            LoggingManager.shared.info(.screenshot, "Captured \(shot.scrollViewScreenshots.count) scroll view screenshots")
            for (index, scrollURL) in shot.scrollViewScreenshots.enumerated() {
                LoggingManager.shared.info(.screenshot, "  Scroll view \(index + 1): \(scrollURL.lastPathComponent)")
            }
        }

        return url
    }
}
