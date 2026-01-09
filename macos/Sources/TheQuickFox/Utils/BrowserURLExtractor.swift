//
//  BrowserURLExtractor.swift
//  TheQuickFox
//
//  Extracts browser URLs using Accessibility API for analytics tracking
//

import Cocoa
import ApplicationServices

public enum BrowserURLExtractor {
    
    public static func extractURL(from appInfo: ActiveWindowInfo) -> String? {
        guard let bundleID = appInfo.bundleID else { return nil }
        
        // Check if it's a browser
        let browserBundleIDs = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.google.Chrome.beta",
            "com.google.Chrome.canary",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "com.apple.SafariTechnologyPreview",
            "company.thebrowser.Browser"  // Arc
        ]
        
        guard browserBundleIDs.contains(bundleID) else { return nil }
        
        // Get the app element
        guard let runningApp = NSRunningApplication(processIdentifier: appInfo.pid) else { return nil }
        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        
        // Get focused window
        var focusedWindow: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        guard focusErr == .success, let windowElement = focusedWindow else { return nil }
        
        // Try to find the URL field
        return findURLInBrowserWindow(windowElement as! AXUIElement, bundleID: bundleID)
    }
    
    private static func findURLInBrowserWindow(_ windowElement: AXUIElement, bundleID: String) -> String? {
        // Safari-specific URL extraction
        if bundleID.contains("Safari") {
            // In Safari, the URL is often in an AXTextField with AXDescription "Address and Search Field"
            if let urlField = findElementByDescription(in: windowElement, description: "Address and Search Field", role: kAXTextFieldRole) {
                if let url = fetchValue(for: urlField) {
                    return url
                }
            }
        }
        
        // Arc browser - uses AXStaticText for URL display (not AXTextField)
        if bundleID.contains("company.thebrowser") {
            if let urlElement = findFirstStaticTextWithURL(in: windowElement) {
                if let url = fetchValue(for: urlElement) {
                    // Arc shows just domain, prepend https://
                    if !url.hasPrefix("http") {
                        return "https://\(url)"
                    }
                    return url
                }
            }
        }

        // Chrome/Chromium-based browsers
        if bundleID.contains("Chrome") || bundleID.contains("com.microsoft.edgemac") || bundleID.contains("com.brave.Browser") {
            // Chrome puts URL in an AXTextField with title "Address and search bar"
            if let urlField = findElementByTitle(in: windowElement, title: "Address and search bar", role: kAXTextFieldRole) {
                if let url = fetchValue(for: urlField) {
                    return url
                }
            }
        }
        
        // Firefox
        if bundleID.contains("firefox") {
            // Firefox uses AXTextField with certain attributes
            if let urlField = findFirstTextFieldWithURL(in: windowElement) {
                if let url = fetchValue(for: urlField) {
                    return url
                }
            }
        }
        
        // Fallback: Look for any text field that looks like it contains a URL
        return findFirstTextFieldWithURL(in: windowElement).flatMap { fetchValue(for: $0) }
    }
    
    private static func findElementByDescription(in parent: AXUIElement, description: String, role: String) -> AXUIElement? {
        var children: AnyObject?
        let childrenErr = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &children)
        guard childrenErr == .success, let childArray = children as? [AXUIElement] else { return nil }
        
        for child in childArray {
            // Check if this element matches
            if let currentRole = fetchRole(for: child), currentRole == role {
                var descValue: AnyObject?
                let descErr = AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descValue)
                if descErr == .success, let desc = descValue as? String, desc == description {
                    return child
                }
            }
            
            // Recurse into children
            if let found = findElementByDescription(in: child, description: description, role: role) {
                return found
            }
        }
        
        return nil
    }
    
    private static func findElementByTitle(in parent: AXUIElement, title: String, role: String) -> AXUIElement? {
        var children: AnyObject?
        let childrenErr = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &children)
        guard childrenErr == .success, let childArray = children as? [AXUIElement] else { return nil }
        
        for child in childArray {
            // Check if this element matches
            if let currentRole = fetchRole(for: child), currentRole == role {
                if let currentTitle = fetchTitle(for: child), currentTitle == title {
                    return child
                }
            }
            
            // Recurse into children
            if let found = findElementByTitle(in: child, title: title, role: role) {
                return found
            }
        }
        
        return nil
    }
    
    /// Find AXStaticText that looks like a URL/domain (used by Arc)
    /// Limited depth to avoid traversing entire accessibility tree
    private static func findFirstStaticTextWithURL(in parent: AXUIElement, depth: Int = 0) -> AXUIElement? {
        // Limit depth to avoid expensive full tree traversal - URL bar is near top
        guard depth < 8 else { return nil }

        var children: AnyObject?
        let childrenErr = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &children)
        guard childrenErr == .success, let childArray = children as? [AXUIElement] else { return nil }

        for child in childArray {
            if let role = fetchRole(for: child), role == kAXStaticTextRole {
                if let value = fetchValue(for: child),
                   value.contains(".") && !value.contains(" ") && value.count < 100 {
                    // Looks like a domain/URL
                    return child
                }
            }

            // Recurse into children with depth limit
            if let found = findFirstStaticTextWithURL(in: child, depth: depth + 1) {
                return found
            }
        }

        return nil
    }

    private static func findFirstTextFieldWithURL(in parent: AXUIElement, debug: Bool = false) -> AXUIElement? {
        var children: AnyObject?
        let childrenErr = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &children)
        guard childrenErr == .success, let childArray = children as? [AXUIElement] else { return nil }

        for child in childArray {
            let role = fetchRole(for: child)
            let title = fetchTitle(for: child)
            let value = fetchValue(for: child)

            if debug {
                var desc: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &desc)
                let descStr = desc as? String
                print("AX Element - role: \(role ?? "nil"), title: \(title ?? "nil"), desc: \(descStr ?? "nil"), value: \(value?.prefix(50) ?? "nil")")
            }

            // Check if this is a text field with URL-like content
            if let role = role, role == kAXTextFieldRole {
                if let value = value,
                   (value.hasPrefix("http://") || value.hasPrefix("https://") || value.contains(".")) {
                    return child
                }
            }

            // Recurse into children
            if let found = findFirstTextFieldWithURL(in: child, debug: debug) {
                return found
            }
        }

        return nil
    }

    /// Debug function to dump Arc's accessibility tree
    public static func debugArcAccessibility(from appInfo: ActiveWindowInfo) {
        guard appInfo.bundleID == "company.thebrowser.Browser" else { return }
        guard let runningApp = NSRunningApplication(processIdentifier: appInfo.pid) else { return }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var focusedWindow: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard focusErr == .success, let windowElement = focusedWindow else { return }

        print("=== Arc Accessibility Debug ===")
        // swiftlint:disable:next force_cast
        _ = findFirstTextFieldWithURL(in: windowElement as! AXUIElement, debug: true)
        print("=== End Arc Debug ===")
    }
    
    // MARK: - Helper methods
    
    private static func fetchRole(for element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return result == .success ? value as? String : nil
    }
    
    private static func fetchTitle(for element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return result == .success ? value as? String : nil
    }
    
    private static func fetchValue(for element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return result == .success ? value as? String : nil
    }
}