import Foundation
import AppKit
import ApplicationServices

/// Capture CLI - Interactive window screenshot and accessibility data capture
///
/// Usage:
///   capture-cli [--output-dir <dir>] [--name <basename>]
///
/// Prompts user to select a window from a list, then captures:
/// - Screenshot (PNG)
/// - Accessibility data (JSON)
///
/// Both files represent the exact same window state.

@main
struct CaptureCLI {
    static func main() async {
        do {
            let args = CommandLine.arguments
            let outputDir = parseArg(args: args, flag: "--output-dir") ?? "."
            let baseName = parseArg(args: args, flag: "--name") ?? "capture-\(Int(Date().timeIntervalSince1970))"

            // Check permissions
            try checkPermissions()

            // List and select window
            print("\n🔍 Scanning for windows...\n")
            guard let windowID = try selectWindowInteractive() else {
                print("❌ No window selected")
                Foundation.exit(1)
            }

            print("\n📸 Capturing window data...\n")

            // Capture screenshot and accessibility data
            let result = try await captureWindow(windowID: windowID)

            // Save files
            let screenshotPath = "\(outputDir)/\(baseName)-screenshot.png"
            let accessibilityPath = "\(outputDir)/\(baseName)-accessibility.json"

            try saveScreenshot(result.screenshot, to: screenshotPath)
            try saveAccessibilityData(result.accessibilityData, to: accessibilityPath)

            print("✅ Capture complete!")
            print("   Screenshot: \(screenshotPath)")
            print("   Accessibility: \(accessibilityPath)")
            print("\n   App bundleID: \(result.bundleID ?? "Unknown")")
            print("   App name: \(result.appName)")
            print("   Active window: \(result.windowTitle ?? "Untitled")")
            print("   Size: \(Int(result.screenshot.size.width))x\(Int(result.screenshot.size.height))")

        } catch {
            print("❌ Error: \(error)")
            Foundation.exit(1)
        }
    }

    // MARK: - Permission Checking

    static func checkPermissions() throws {
        // Check screen recording permission
        guard CGPreflightScreenCaptureAccess() else {
            print("⚠️  Screen Recording permission required")
            print("   Go to: System Settings > Privacy & Security > Screen Recording")
            throw CaptureError.screenRecordingPermissionDenied
        }

        // Check accessibility permission
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️  Accessibility permission required")
            print("   Go to: System Settings > Privacy & Security > Accessibility")
            throw CaptureError.accessibilityPermissionDenied
        }
    }

    // MARK: - Window Listing and Selection

    static func selectWindowInteractive() throws -> CGWindowID? {
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            throw CaptureError.windowListFailed
        }

        // Filter and format windows
        let windows: [(id: CGWindowID, app: String, title: String, size: String, pid: pid_t)] = windowList.compactMap { info in
            guard
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let width = bounds["Width"] as? CGFloat,
                let height = bounds["Height"] as? CGFloat,
                width > 100, height > 100
            else {
                return nil
            }

            let ownerApp = NSRunningApplication(processIdentifier: pid)
            let appName = ownerApp?.localizedName ?? "Unknown"
            let windowTitle = info[kCGWindowName as String] as? String ?? ""

            // Skip TheQuickFox
            if let bundleID = ownerApp?.bundleIdentifier,
               bundleID.contains("TheQuickFox") {
                return nil
            }

            let sizeStr = "\(Int(width))x\(Int(height))"

            return (id: windowID, app: appName, title: windowTitle, size: sizeStr, pid: pid)
        }

        guard !windows.isEmpty else {
            print("No windows available for capture")
            return nil
        }

        // Display window list
        print("Available Windows:")
        print(String(repeating: "=", count: 60))
        for (index, window) in windows.enumerated() {
            let displayTitle = window.title.isEmpty ? "[No Title]" : window.title
            print("\(index + 1). [\(window.app)] \(displayTitle)")
            print("   Size: \(window.size)")
        }
        print()

        // Get user selection
        print("Enter window number (or 0 to cancel): ", terminator: "")
        fflush(stdout)

        guard let input = readLine(),
              let selection = Int(input),
              selection > 0,
              selection <= windows.count else {
            return nil
        }

        return windows[selection - 1].id
    }

    // MARK: - Window Capture

    struct CaptureResult {
        let screenshot: NSImage
        let accessibilityData: AccessibilityData
        let bundleID: String?
        let appName: String
        let windowTitle: String?
        let pid: pid_t
    }

    static func captureWindow(windowID: CGWindowID) async throws -> CaptureResult {
        // Get window info
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]],
            let windowInfo = windowList.first(where: {
                ($0[kCGWindowNumber as String] as? CGWindowID) == windowID
            })
        else {
            throw CaptureError.windowNotFound
        }

        let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let ownerApp = NSRunningApplication(processIdentifier: pid)
        let bundleID = ownerApp?.bundleIdentifier
        let appName = ownerApp?.localizedName ?? "Unknown"
        let windowTitle = windowInfo[kCGWindowName as String] as? String

        // Capture screenshot
        guard
            let cgImage = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw CaptureError.screenshotFailed
        }

        let screenshot = NSImage(cgImage: cgImage, size: .zero)

        // Capture accessibility data
        let accessibilityData = try await captureAccessibilityData(pid: pid)

        return CaptureResult(
            screenshot: screenshot,
            accessibilityData: accessibilityData,
            bundleID: bundleID,
            appName: appName,
            windowTitle: windowTitle,
            pid: pid
        )
    }

    // MARK: - Accessibility Capture

    struct AccessibilityData: Codable {
        let appInfo: AppInfo
        let roleTree: RoleNode?
        let textElements: [TextElement]
        let uiElements: [UIElement]
        let captureTimestamp: String

        struct AppInfo: Codable {
            let bundleID: String?
            let appName: String?
            let windowTitle: String?
            let pid: Int32
        }

        struct RoleNode: Codable {
            let role: String
            let subroles: [RoleNode]
        }

        struct TextElement: Codable {
            let text: String
            let role: String
            let isVisible: Bool
        }

        struct UIElement: Codable {
            let role: String
            let title: String?
            let value: String?
            let isVisible: Bool
        }
    }

    static func captureAccessibilityData(pid: pid_t) async throws -> AccessibilityData {
        let app = AXUIElementCreateApplication(pid)

        // Get focused window
        var focusedWindowRef: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )

        guard focusedError == .success,
              let focusedWindow = focusedWindowRef else {
            throw CaptureError.accessibilityFailed
        }

        let ownerApp = NSRunningApplication(processIdentifier: pid)

        // Get window title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        let windowTitle = titleRef as? String

        // Build role tree
        let roleTree = try? buildRoleTree(element: focusedWindow as! AXUIElement, maxDepth: 5)

        // Extract text and UI elements
        let (textElements, uiElements) = try extractElements(from: focusedWindow as! AXUIElement)

        return AccessibilityData(
            appInfo: AccessibilityData.AppInfo(
                bundleID: ownerApp?.bundleIdentifier,
                appName: ownerApp?.localizedName,
                windowTitle: windowTitle,
                pid: pid
            ),
            roleTree: roleTree,
            textElements: textElements,
            uiElements: uiElements,
            captureTimestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func buildRoleTree(element: AXUIElement, maxDepth: Int, currentDepth: Int = 0) throws -> AccessibilityData.RoleNode? {
        guard currentDepth < maxDepth else { return nil }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return nil
        }

        var childrenRef: CFTypeRef?
        var subroles: [AccessibilityData.RoleNode] = []

        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            subroles = children.compactMap { child in
                try? buildRoleTree(element: child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
            }
        }

        return AccessibilityData.RoleNode(role: role, subroles: subroles)
    }

    static func extractElements(from window: AXUIElement) throws -> ([AccessibilityData.TextElement], [AccessibilityData.UIElement]) {
        var textElements: [AccessibilityData.TextElement] = []
        var uiElements: [AccessibilityData.UIElement] = []

        func traverse(_ element: AXUIElement, depth: Int = 0) {
            guard depth < 8 else { return }

            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else {
                return
            }

            // Extract text
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String,
               !value.isEmpty {
                textElements.append(AccessibilityData.TextElement(
                    text: value,
                    role: role,
                    isVisible: true
                ))
            }

            // Extract UI element
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String

            if role == "AXButton" || role == "AXTextField" || role == "AXStaticText" {
                uiElements.append(AccessibilityData.UIElement(
                    role: role,
                    title: title,
                    value: valueRef as? String,
                    isVisible: true
                ))
            }

            // Traverse children
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    traverse(child, depth: depth + 1)
                }
            }
        }

        traverse(window)

        return (textElements, uiElements)
    }

    // MARK: - File Saving

    static func saveScreenshot(_ image: NSImage, to path: String) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw CaptureError.screenshotSaveFailed
        }

        try pngData.write(to: URL(fileURLWithPath: path))
    }

    static func saveAccessibilityData(_ data: AccessibilityData, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Helpers

    static func parseArg(args: [String], flag: String) -> String? {
        guard let index = args.firstIndex(of: flag),
              index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    enum CaptureError: Error, CustomStringConvertible {
        case screenRecordingPermissionDenied
        case accessibilityPermissionDenied
        case windowListFailed
        case windowNotFound
        case screenshotFailed
        case accessibilityFailed
        case screenshotSaveFailed

        var description: String {
            switch self {
            case .screenRecordingPermissionDenied:
                return "Screen Recording permission denied"
            case .accessibilityPermissionDenied:
                return "Accessibility permission denied"
            case .windowListFailed:
                return "Failed to get window list"
            case .windowNotFound:
                return "Window not found"
            case .screenshotFailed:
                return "Failed to capture screenshot"
            case .accessibilityFailed:
                return "Failed to capture accessibility data"
            case .screenshotSaveFailed:
                return "Failed to save screenshot"
            }
        }
    }
}
