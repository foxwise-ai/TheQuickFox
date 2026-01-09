//
//  WindowSelector.swift
//  TheQuickFox
//
//  Shared window selection logic for finding the best window to interact with.
//  Used by both screenshot capture and window highlighting to ensure consistency.
//

import Cocoa
import CoreGraphics

public enum WindowSelector {
    
    /// Finds the best window for a given process ID from a window list.
    ///
    /// Selection priority:
    /// 1. Windows with non-empty titles (visible, user-facing windows)
    /// 2. First valid window that passes all filters
    /// 3. Fallback window if no valid windows found
    ///
    /// - Parameters:
    ///   - targetPID: Process ID of the target application
    ///   - windowList: Array of window info dictionaries from CGWindowListCopyWindowInfo
    ///   - fallback: Fallback window info to use if no valid window is found
    /// - Returns: The best matching window info dictionary, or nil if none found
    public static func findBestWindow(
        targetPID: pid_t,
        windowList: [[String: Any]],
        fallback: [String: Any]? = nil
    ) -> [String: Any]? {
        
        let candidateWindows = windowList.filter { info in
            guard
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                pid == targetPID,
                let alpha = info[kCGWindowAlpha as String] as? CGFloat,
                alpha > 0.05,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer <= 100,
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let w = bounds["Width"] as? CGFloat,
                let h = bounds["Height"] as? CGFloat,
                w > 100,
                h > 100
            else { return false }
            
            if let ownerApp = NSRunningApplication(processIdentifier: pid),
               let bundleID = ownerApp.bundleIdentifier,
               bundleID.contains("TheQuickFox") {
                return false
            }
            
            return true
        }
        
        let windowWithTitle = candidateWindows.first { info in
            if let title = info[kCGWindowName as String] as? String, !title.isEmpty {
                return true
            }
            return false
        }
        
        return windowWithTitle ?? candidateWindows.first ?? fallback
    }
}
