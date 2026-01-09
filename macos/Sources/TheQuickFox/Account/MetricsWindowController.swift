//
//  MetricsWindowController.swift
//  TheQuickFox
//
//  Manages the metrics/analytics window for usage statistics and insights
//

import Cocoa
import SwiftUI
import Combine

// Custom window that can always become key (needed for accessory apps)
class MetricsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class MetricsWindowController: NSWindowController, NSWindowDelegate {

    static var shared: MetricsWindowController?

    override func awakeFromNib() {
        super.awakeFromNib()
        self.window?.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // No need to change activation policy - we're always in regular mode
    }

    convenience init() {
        // Create a custom window that can properly become key
        let window = MetricsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Statistics"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        // Set delegate to handle window close
        window.delegate = self

        // Create SwiftUI view
        let contentView = MetricsDashboardView()
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView

        // Force the window to accept first responder
        window.makeFirstResponder(window)

        // Set minimum window size
        window.minSize = NSSize(width: 600, height: 500)

        // IMPORTANT: This fixes the paste issue by ensuring the window accepts key events
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
    }

    static func show() {
        if shared == nil {
            shared = MetricsWindowController()
        }

        // Fetch latest metrics when window is shown
        AppStore.shared.dispatch(.metrics(.startFetch(timeRange: "30d")))

        // Activate app first
        NSApp.activate(ignoringOtherApps: true)

        // Ensure window comes to front with aggressive ordering
        DispatchQueue.main.async {
            shared?.window?.orderFrontRegardless()
            shared?.window?.makeKeyAndOrderFront(nil)
            shared?.window?.makeMain()
            shared?.window?.makeKey()
        }
    }
}
