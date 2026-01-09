//
//  ApplicationContextProvider.swift
//  TheQuickFox
//
//  Supplies metadata about the currently-active macOS application as well as a
//  lightweight Accessibility-based UI role hierarchy.  Used by Task 4 to feed
//  downstream prompt generation.
//
//  NOTE: The process running this code must have the “Accessibility” permission
//  (System Settings ▸ Privacy & Security ▸ Accessibility), otherwise calls will
//  fail with `AXError`.  The helper surfaces those as Swift errors so the UI can
//  present a permissions prompt.
//
//  Created by TheQuickFox Auto-Generator.
//

import Cocoa
import ApplicationServices

// MARK: - Public Model Types

/// Simple recursive representation of an Accessibility role hierarchy.
public struct AXRoleNode: Codable, Hashable {
    public let role: String
    public let subroles: [AXRoleNode]

    public init(role: String, subroles: [AXRoleNode] = []) {
        self.role = role
        self.subroles = subroles
    }
}

/// Errors that can be thrown by `ApplicationContextProvider`.
public enum ApplicationContextError: Error {
    case accessibilityDenied
    case windowUnavailable
    case axError(AXError)
}

// MARK: - Provider

public enum ApplicationContextProvider {

    /// Fetches high-level metadata and (optionally) an Accessibility role tree
    /// for the currently front-most application window.
    ///
    /// - Parameter includeRoleTree: When `true`, collects a shallow hierarchy
    ///   (depth ≤ 3) of AXRoles starting at the focused window.
    /// - Returns: `ActiveWindowInfo` plus optional `AXRoleNode` root.
    /// - Throws: `ApplicationContextError` if data cannot be retrieved.
    public static func fetch(
        includeRoleTree: Bool = true,
        maxDepth: Int = 3
    ) throws -> (info: ActiveWindowInfo, roleTree: AXRoleNode?) {

        // 1. Identify the active application.
        guard let runningApp = NSWorkspace.shared.frontmostApplication else {
            throw ApplicationContextError.windowUnavailable
        }

        let pid = runningApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // 2. Fetch the focused window via AX.
        var focusedWindow: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard focusErr == .success, let windowElement = focusedWindow else {
            if focusErr == .apiDisabled {
                throw ApplicationContextError.accessibilityDenied
            }
            throw ApplicationContextError.axError(focusErr)
        }

        // 3. Retrieve window title.
        var titleValue: AnyObject?
        let titleErr = AXUIElementCopyAttributeValue(
            windowElement as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        let windowTitle: String? =
            (titleErr == .success) ? (titleValue as? String) : nil

        // 4. Assemble ActiveWindowInfo.
        let info = ActiveWindowInfo(
            bundleID: runningApp.bundleIdentifier,
            appName: runningApp.localizedName,
            windowTitle: windowTitle,
            pid: pid
        )

        // 5. Optionally build a role hierarchy.
        let roleTree: AXRoleNode? = includeRoleTree
            ? try buildRoleHierarchy(
                from: windowElement as! AXUIElement,
                currentDepth: 0,
                maxDepth: maxDepth
            )
            : nil

        return (info, roleTree)
    }

    // MARK: - Private helpers

    /// Recursively constructs an `AXRoleNode` tree up to `maxDepth`.
    private static func buildRoleHierarchy(
        from element: AXUIElement,
        currentDepth: Int,
        maxDepth: Int
    ) throws -> AXRoleNode {

        // Guard depth.
        if currentDepth >= maxDepth {
            return AXRoleNode(role: fetchRole(for: element))
        }

        // Fetch children.
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        if err != .success && err != .noValue {
            throw ApplicationContextError.axError(err)
        }

        let children = (childrenValue as? [AXUIElement]) ?? []
        let subroles = try children.map {
            try buildRoleHierarchy(
                from: $0,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth
            )
        }

        return AXRoleNode(
            role: fetchRole(for: element),
            subroles: subroles
        )
    }

    /// Convenience to obtain the AXRole of an element, falling back to "<unknown>"
    private static func fetchRole(for element: AXUIElement) -> String {
        var roleValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        if err == .success, let role = roleValue as? String {
            return role
        }
        return "<unknown>"
    }
}
