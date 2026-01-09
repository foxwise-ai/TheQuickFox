//
//  FocusManager.swift
//  TheQuickFox
//
//  Captures and restores keyboard focus around the HUD lifecycle and provides
//  helpers to insert text into the previously-focused field.  Works entirely
//  through the macOS Accessibility API so no clipboard tricks are required.
//
//  NOTE: • The running process must have Accessibility permissions.
//        • Fallbacks to synthetic keystrokes when AXValueSet fails.
//
//  Created by TheQuickFox.
//

import ApplicationServices
import Cocoa

public enum FocusManagerError: Error {
    case accessibilityDenied
    case focusedElementUnavailable
    case insertionFailed
}

/// Manages the previously-focused text element so we can later insert the
/// generated reply.
public final class FocusManager {

    // MARK: Singleton
    public static let shared = FocusManager()
    private init() {}

    // MARK: Private State
    private var storedElement: AXUIElement?
    private var storedAppPID: pid_t = 0
    private var storedWindow: AXUIElement?

    /// Capture the currently-focused UI element (typically a text field or
    /// textarea) *before* the HUD steals key status.
    /// Returns true if a text-editable element was captured.
    @discardableResult
    public func captureCurrentFocus() throws -> Bool {
        guard AXIsProcessTrusted() else { throw FocusManagerError.accessibilityDenied }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw FocusManagerError.focusedElementUnavailable
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )

        guard err == .success, let element = focused else {
            throw FocusManagerError.focusedElementUnavailable
        }

        let axElement = element as! AXUIElement
        storedElement = axElement
        storedAppPID = frontApp.processIdentifier

        // Also capture the window containing this element
        var window: AnyObject?
        let windowErr = AXUIElementCopyAttributeValue(
            axElement,
            kAXWindowAttribute as CFString,
            &window
        )
        if windowErr == .success, let windowElement = window {
            storedWindow = (windowElement as! AXUIElement)
            print("DEBUG: Captured window for focus restoration")
        }

        // Debug: print element info
        if let role = getElementAttribute(axElement, kAXRoleAttribute as CFString) {
            print("DEBUG: Focused element role: \(role)")
        }
        if let value = getElementAttribute(axElement, kAXValueAttribute as CFString) {
            print("DEBUG: Current element value: '\(value)'")
        }

        return isElementTextEditable(axElement)
    }

    /// Insert the generated text into the previously-focused element and restore
    /// application focus.  If direct insertion fails, falls back to pasting via
    /// synthetic ⌘V (clipboard content is preserved/restored).
    ///
    /// - Parameters:
    ///   - reply: The text to insert.
    /// - Returns: nil if text was successfully inserted, InsertionFailureReason otherwise
    @discardableResult
    public func insertReplyAndRestoreFocus(_ reply: String) -> InsertionFailureReason? {
        guard let element = storedElement else {
            return .elementUnavailable
        }

        // Bring original app forward and explicitly restore focus to the element.
        var isTerminalApp = false
        var isBrowserApp = false
        var isElectronApp = false
        if let app = NSRunningApplication(processIdentifier: storedAppPID) {
            app.activate(options: .activateIgnoringOtherApps)

            // Bring the specific window to front if we have it
            if let window = storedWindow {
                // Raise the window to front
                let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                if raiseResult == .success {
                    print("DEBUG: Successfully raised window to front")
                } else {
                    print("DEBUG: Failed to raise window: \(raiseResult.rawValue)")
                }

                // Set it as the focused window
                let focusResult = AXUIElementSetAttributeValue(
                    window,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
                if focusResult == .success {
                    print("DEBUG: Successfully focused window")
                } else {
                    print("DEBUG: Failed to focus window: \(focusResult.rawValue)")
                }
            }

            // Check if this is a terminal, browser, or Electron application, as they require special handling.
            if let bundleId = app.bundleIdentifier?.lowercased() {
                isTerminalApp = bundleId.contains("iterm") || bundleId.contains("terminal")

                let browserFragments = [
                    "safari", "chrome", "firefox", "arc", "company.thebrowser.browser",
                ]
                isBrowserApp = browserFragments.contains { fragment in bundleId.contains(fragment) }

                // Detect Electron apps by checking for Electron Framework in app bundle
                if let bundleURL = app.bundleURL {
                    let electronFrameworkPath = bundleURL.appendingPathComponent(
                        "Contents/Frameworks/Electron Framework.framework")
                    isElectronApp = FileManager.default.fileExists(
                        atPath: electronFrameworkPath.path)
                    if isElectronApp {
                        print("DEBUG: Detected Electron app via framework folder: \(bundleId)")
                    }
                }
            }

            // Some apps drop the text-field focus when TheQuickFox becomes active.
            // Re-assigning the AXFocusedUIElement ensures subsequent insertion or
            // synthetic paste operations target the correct control.
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            _ = AXUIElementSetAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                element)

            // Wait for app activation to complete, especially important for some apps.
            Thread.sleep(forTimeInterval: 0.2)
        }

        // For terminal apps, type text directly. For browsers and Electron apps, direct AX insertion is
        // unreliable, so we default to pasting. For others, try AX first.
        var failureReason: InsertionFailureReason? = nil

        if isTerminalApp {
            print("DEBUG: Terminal app detected, using direct typing.")
            do {
                try typeText(reply)
                // For terminals, we can't reliably verify, so assume success if no exception
                failureReason = nil
            } catch {
                print("DEBUG: Terminal typing failed: \(error)")
                failureReason = .appNotResponding
            }
        } else if isBrowserApp {
            print("DEBUG: Browser app detected, using fallback paste with focus restoration.")
            do {
                try clickElement(element)
                Thread.sleep(forTimeInterval: 0.15)
                let pasteSucceeded = try fallbackPaste(reply, target: element)
                failureReason = pasteSucceeded ? nil : .clipboardFailed
            } catch {
                print("DEBUG: Browser paste failed: \(error)")
                failureReason = .clipboardFailed
            }
        } else if isElectronApp {
            print("DEBUG: Electron app detected, using fallback paste.")
            do {
                let pasteSucceeded = try fallbackPaste(reply, target: element)
                failureReason = pasteSucceeded ? nil : .clipboardFailed
            } catch {
                print("DEBUG: Electron paste failed: \(error)")
                failureReason = .clipboardFailed
            }
        } else {
            // Attempt AX insertion for other applications.
            print("DEBUG: Attempting direct AX insertion for non-browser/non-terminal app.")
            if !setAXStringValue(reply, on: element) {
                // Fallback to clipboard + paste if AX insertion fails.
                print("DEBUG: AX insertion failed, using fallback paste.")
                do {
                    let pasteSucceeded = try fallbackPaste(reply, target: element)
                    failureReason = pasteSucceeded ? nil : .clipboardFailed
                } catch {
                    print("DEBUG: Fallback paste failed: \(error)")
                    failureReason = .clipboardFailed
                }
            } else {
                print("DEBUG: AX insertion successful.")
                failureReason = nil
            }
        }

        // Clear internal state.
        storedElement = nil
        storedAppPID = 0
        storedWindow = nil

        return failureReason
    }

    // MARK: - Private helpers

    /// Check if the given element is text-editable
    private func isElementTextEditable(_ element: AXUIElement) -> Bool {
        // Check role first
        guard let role = getElementAttribute(element, kAXRoleAttribute as CFString) else {
            return false
        }

        // Common text-editable roles - these are definitely text inputs
        let textEditableRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]

        if textEditableRoles.contains(role) {
            print("DEBUG: Element is text-editable (role: \(role))")
            return true
        }

        // For web content, check if it's a focused text element with specific subrole
        if role == kAXGroupRole as String || role == kAXStaticTextRole as String {
            // Check if it has insertion point or is editable
            var insertionPoint: AnyObject?
            let insertionResult = AXUIElementCopyAttributeValue(
                element,
                kAXInsertionPointLineNumberAttribute as CFString,
                &insertionPoint
            )

            if insertionResult == .success {
                print("DEBUG: Element is text-editable (has insertion point)")
                return true
            }

            // Check selected text range (indicates text cursor)
            var selectedRange: AnyObject?
            let rangeResult = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &selectedRange
            )

            if rangeResult == .success {
                print("DEBUG: Element is text-editable (has text selection)")
                return true
            }
        }

        print("DEBUG: Element is NOT text-editable (role: \(role))")
        return false
    }

    /// Try common AX attributes for text insertion.
    /// For terminals, uses caret position for insertion.
    private func setAXStringValue(_ value: String, on element: AXUIElement) -> Bool {
        print("DEBUG: Trying insertion at caret position...")

        // First try to get the insertion point/caret position
        var insertionPoint: AnyObject?
        let insertionError = AXUIElementCopyAttributeValue(
            element,
            kAXInsertionPointLineNumberAttribute as CFString,
            &insertionPoint)

        if insertionError == .success {
            print("DEBUG: Found insertion point")
        }

        // Try to use AXSelectedTextRange to insert at caret
        var caretRange: AnyObject?
        let caretError = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &caretRange)

        if caretError == .success, caretRange != nil {
            print("DEBUG: Found caret range, attempting insertion...")
            // Set the selected text at caret position
            let setError = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                value as CFTypeRef)
            if setError == .success {
                print("DEBUG: Caret insertion API call succeeded, verifying...")
                // Verify the text was actually inserted
                Thread.sleep(forTimeInterval: 0.1) // Give it a moment to update
                if verifyTextInserted(element, expectedText: value) {
                    print("DEBUG: Caret insertion verified successful")
                    return true
                } else {
                    print("DEBUG: Caret insertion verification failed - text not found in field")
                }
            } else {
                print("DEBUG: Caret insertion failed with error: \(setError.rawValue)")
            }
        }

        // Fallback to traditional approaches
        let attributes: [CFString] = [
            kAXSelectedTextAttribute as CFString,
            kAXValueAttribute as CFString,
        ]

        for attr in attributes {
            let error = AXUIElementSetAttributeValue(element, attr, value as CFTypeRef)
            if error == .success {
                print("DEBUG: Attribute \(attr) set successfully, verifying...")
                Thread.sleep(forTimeInterval: 0.1)
                if verifyTextInserted(element, expectedText: value) {
                    print("DEBUG: Insertion via \(attr) verified successful")
                    return true
                } else {
                    print("DEBUG: Insertion via \(attr) verification failed")
                }
            }
        }
        return false
    }

    /// Verify that text was actually inserted by reading back the field value
    private func verifyTextInserted(_ element: AXUIElement, expectedText: String) -> Bool {
        // Get the current value from the element
        if let currentValue = getAXStringValue(from: element) {
            // Check if the expected text is contained in the current value
            // We use contains instead of == because some apps may have existing text
            let contains = currentValue.contains(expectedText)
            print("DEBUG: Verification - Expected text \(contains ? "found" : "NOT found") in field")
            return contains
        }

        print("DEBUG: Verification failed - could not read field value")
        return false
    }

    /// Helper to get current text value from an AX element
    private func getAXStringValue(from element: AXUIElement) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard error == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    /// Helper to get any attribute from an AX element
    private func getElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    /// Fallback path: copy original clipboard, set our reply, paste, then restore.
    /// Returns true if paste was verified successful, false otherwise.
    private func fallbackPaste(_ reply: String, target: AXUIElement) throws -> Bool {
        let pb = NSPasteboard.general

        // Create a deep copy of the original pasteboard items. Reading `pb.pasteboardItems`
        // returns item objects that cannot be re-written directly. We must reconstruct them
        // to avoid a crash when restoring.
        let previousItems = pb.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }

        // Write reply to clipboard
        pb.clearContents()
        pb.setString(reply, forType: .string)

        // Additional delay to ensure target app is fully active (critical for iTerm2)
        Thread.sleep(forTimeInterval: 0.1)

        // Paste via synthetic ⌘V
        simulateKeystroke(key: 0x09, flags: .maskCommand)  // 0x09 = 'v'

        // Wait for paste to complete and verify
        Thread.sleep(forTimeInterval: 0.3)

        let success = verifyTextInserted(target, expectedText: reply)
        if success {
            print("DEBUG: Fallback paste verified successful")
        } else {
            print("DEBUG: Fallback paste verification failed - text not found in field")
        }

        // Restore previous clipboard asynchronously
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pb.clearContents()
            if let items = previousItems {
                pb.writeObjects(items)
            }
        }

        return success
    }

    /// Type text character by character using synthetic keystrokes (for terminals)
    private func typeText(_ text: String) throws {
        // Additional delay to ensure terminal is ready
        Thread.sleep(forTimeInterval: 0.1)

        for char in text {
            if char == "\n" || char == "\r" {
                // Convert newline to Enter key press
                typeEnterKey()
            } else {
                typeCharacter(char)
            }
            // Small delay between characters for reliable typing
            usleep(2000)  // 2ms delay between characters
        }
    }

    /// Send an Enter key press
    private func typeEnterKey() {
        simulateKeystroke(key: 0x24, flags: [])  // 0x24 = Return key
    }

    /// Type a single character using synthetic keyboard events
    private func typeCharacter(_ char: Character) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Create keyboard event with the Unicode character
        if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            let text = String(char)
            event.keyboardSetUnicodeString(
                stringLength: text.count, unicodeString: Array(text.utf16))
            event.post(tap: .cgSessionEventTap)
        }

        // Small delay for character processing
        usleep(1000)  // 1ms

        if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            let text = String(char)
            event.keyboardSetUnicodeString(
                stringLength: text.count, unicodeString: Array(text.utf16))
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Send a single synthetic key press to the system.
    /// Uses the most compatible event posting strategy for terminals.
    private func simulateKeystroke(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyUp?.flags = flags

        // Use session event tap for terminal compatibility
        keyDown?.post(tap: .cgSessionEventTap)

        // Small delay between key down and key up for better compatibility
        usleep(10000)  // 10ms delay

        keyUp?.post(tap: .cgSessionEventTap)
    }

    /// Click an element to ensure it receives focus (especially important for web compose fields)
    private func clickElement(_ element: AXUIElement) throws {
        var position: AnyObject?
        let posError = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &position
        )
        
        guard posError == .success, let posValue = position else {
            print("DEBUG: Could not get element position for click")
            return
        }
        
        var point = CGPoint.zero
        if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
            var size: AnyObject?
            let sizeError = AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &size
            )
            
            if sizeError == .success, let sizeValue = size {
                var elementSize = CGSize.zero
                if AXValueGetValue(sizeValue as! AXValue, .cgSize, &elementSize) {
                    let clickPoint = CGPoint(
                        x: point.x + elementSize.width / 2,
                        y: point.y + elementSize.height / 2
                    )
                    
                    let source = CGEventSource(stateID: .hidSystemState)
                    if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
                       let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) {
                        mouseDown.post(tap: .cghidEventTap)
                        usleep(50000)
                        mouseUp.post(tap: .cghidEventTap)
                        print("DEBUG: Clicked element at \(clickPoint)")
                    }
                }
            }
        }
    }
}
