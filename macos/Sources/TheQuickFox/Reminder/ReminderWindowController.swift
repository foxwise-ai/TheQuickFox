//
//  ReminderWindowController.swift
//  TheQuickFox
//
//  Shows a quick reminder of the Control+Control shortcut when dock icon is clicked
//

import Cocoa
import WebKit

// Custom window that can always become key
class ReminderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ReminderWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    // MARK: - Properties

    static var shared: ReminderWindowController?
    private var webView: WKWebView!

    // MARK: - Initialization

    convenience init() {
        let window = ReminderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "TheQuickFox"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self

        setupWebView()
        loadReminderContent()
    }

    // MARK: - Setup

    private func setupWebView() {
        guard let window = window else { return }

        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "reminder")
        configuration.userContentController = userContentController

        webView = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self

        // Configure appearance
        webView.wantsLayer = true
        if #available(macOS 10.14, *) {
            webView.setValue(false, forKey: "drawsBackground")
        }

        window.contentView = webView
    }

    private func loadReminderContent() {
        let fileManager = FileManager.default
        var htmlURL: URL?
        var baseURL: URL?

        let possiblePaths = [
            Bundle.main.resourceURL?.appendingPathComponent("Reminder/reminder.html"),
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("TheQuickFox_TheQuickFox.resources/Reminder/reminder.html"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Sources/TheQuickFox/Reminder/Resources/reminder.html"),
        ]

        for path in possiblePaths.compactMap({ $0 }) {
            if fileManager.fileExists(atPath: path.path) {
                htmlURL = path
                baseURL = path.deletingLastPathComponent()
                break
            }
        }

        guard let finalURL = htmlURL, let finalBaseURL = baseURL else {
            print("❌ Could not find reminder.html")
            return
        }

        webView.loadFileURL(finalURL, allowingReadAccessTo: finalBaseURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Set system appearance
        if #available(macOS 10.14, *) {
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            webView.evaluateJavaScript("window.setSystemAppearance?.('\(isDarkMode ? "dark" : "light")')")
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "openSettings":
            AccountWindowController.show()
            window?.close()
        case "close":
            window?.close()
        default:
            break
        }
    }

    // MARK: - Public Methods

    static func show() {
        if shared == nil {
            shared = ReminderWindowController()
        }

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            shared?.window?.center()
            shared?.window?.orderFrontRegardless()
            shared?.window?.makeKeyAndOrderFront(nil)
        }
    }
}
