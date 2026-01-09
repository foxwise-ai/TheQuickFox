//
//  PermissionsState.swift
//  TheQuickFox
//
//  Tracks the state of system permissions
//

import Foundation
import Cocoa

/// Global state for tracking system permissions
final class PermissionsState {
    static let shared = PermissionsState()

    private init() {}

    /// Whether the app has accessibility permissions for keyboard monitoring
    var hasAccessibilityPermissions = false

    /// Whether the app has screen recording permissions for screenshots
    var hasScreenRecordingPermissions = false

    /// Check if we have screen recording permissions by attempting to capture a window
    func checkScreenRecordingPermission() -> Bool {
        // We need to test the exact same operation that WindowScreenshotter uses:
        // capturing a specific window by its ID

        // First, get the frontmost window (excluding desktop elements)
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]],
        !windowList.isEmpty else {
            // Can't get window list at all
            hasScreenRecordingPermissions = false
            print("❌ Screen recording permission: DENIED (empty window list)")
            return false
        }

        print("🔍 Found \(windowList.count) windows for permission check")

        // Find a window that's not from our app
        var testWindowID: CGWindowID? = nil
        var testWindowInfo: String = ""

        for window in windowList {
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let windowName = window[kCGWindowName as String] as? String ?? "Untitled"

            // Skip our own windows
            if ownerName == "TheQuickFox" {
                continue
            }

            if let windowID = window[kCGWindowNumber as String] as? CGWindowID {
                testWindowID = windowID
                testWindowInfo = "\(ownerName) - '\(windowName)' (ID: \(windowID))"
                break
            }
        }

        guard let windowID = testWindowID else {
            hasScreenRecordingPermissions = false
            print("❌ Screen recording permission: DENIED (no test window found)")
            return false
        }

        print("🔍 Testing capture on window: \(testWindowInfo)")

        // Try to capture that window - this is exactly what fails in WindowScreenshotter
        if let image = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            // Successfully created an image - we have permission
            hasScreenRecordingPermissions = true
            let width = image.width
            let height = image.height
            print("✅ Screen recording permission: GRANTED (captured \(width)x\(height) image)")
        } else {
            // Failed to create image - no permission
            hasScreenRecordingPermissions = false
            print("❌ Screen recording permission: DENIED (CGWindowListCreateImage returned nil)")
        }

        return hasScreenRecordingPermissions
    }

    /// Check if we have accessibility permissions
    func checkAccessibilityPermission() -> Bool {
        hasAccessibilityPermissions = AXIsProcessTrusted()
        return hasAccessibilityPermissions
    }

    /// Check all permissions and return their status
    func checkAllPermissions() -> (accessibility: Bool, screenRecording: Bool) {
        return (
            accessibility: checkAccessibilityPermission(),
            screenRecording: checkScreenRecordingPermission()
        )
    }
}
