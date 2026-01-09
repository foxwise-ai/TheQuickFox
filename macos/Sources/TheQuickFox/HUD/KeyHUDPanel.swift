import AppKit

/// A custom `NSPanel` that can become the key window.
public final class KeyHUDPanel: NSPanel {
    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return true
    }
    
    public override func cancelOperation(_ sender: Any?) {
        // Handle ESC key
        if let viewController = contentViewController as? HUDViewController {
            viewController.handleEscapeKey()
        }
    }
}
