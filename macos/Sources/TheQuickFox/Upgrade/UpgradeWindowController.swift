//
//  UpgradeWindowController.swift
//  TheQuickFox
//
//  Shows upgrade prompt when trial quota is exceeded
//

import Cocoa
import WebKit

final class UpgradeWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Singleton

    static let shared = UpgradeWindowController()

    // MARK: - Properties

    var upgradeWebView: WKWebView!
    private var messageHandler: UpgradeMessageHandler!
    private var remainingQueries: Int = 0
    private var selectedPriceType: String = "yearly"

    // MARK: - Initialization

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Upgrade to TheQuickFox Pro"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.minSize = NSSize(width: 800, height: 500)

        super.init(window: window)
        
        window.delegate = self
        
        // Initialize message handler
        messageHandler = UpgradeMessageHandler()
        messageHandler.windowController = self
        
        setupWebView()
        loadUpgradeContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        guard let window = window else { return }
        
        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Add message handler
        userContentController.add(messageHandler, name: "upgrade")
        configuration.userContentController = userContentController
        
        // Create web view
        upgradeWebView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        upgradeWebView.autoresizingMask = [.width, .height]
        
        // Configure appearance
        upgradeWebView.wantsLayer = true
        if #available(macOS 10.14, *) {
            upgradeWebView.setValue(false, forKey: "drawsBackground")
            upgradeWebView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        // Enable developer extras for debugging
        #if DEBUG
        upgradeWebView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        
        // Set navigation delegate
        upgradeWebView.navigationDelegate = self
        
        window.contentView = upgradeWebView
    }
    
    private func loadUpgradeContent() {
        let fileManager = FileManager.default
        var htmlURL: URL?
        var baseURL: URL?
        
        // Try multiple paths
        let possiblePaths = [
            // App bundle Resources folder
            Bundle.main.resourceURL?.appendingPathComponent("Upgrade/upgrade.html"),
            // Swift Package Manager resources
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("TheQuickFox_TheQuickFox.resources/Upgrade/upgrade.html"),
            // Development path
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Sources/TheQuickFox/Upgrade/Resources/upgrade.html"),
        ]
        
        for path in possiblePaths.compactMap({ $0 }) {
            if fileManager.fileExists(atPath: path.path) {
                htmlURL = path
                baseURL = path.deletingLastPathComponent()
                break
            }
        }
        
        guard let finalURL = htmlURL, let finalBaseURL = baseURL else {
            print("❌ Could not find upgrade HTML file")
            return
        }
        
        upgradeWebView.loadFileURL(finalURL, allowingReadAccessTo: finalBaseURL)
    }

    // MARK: - Public Methods

    func showUpgradePrompt() {
        window?.center()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Reload HTML to reset state
        loadUpgradeContent()

        // Fetch and show pricing
        fetchPricingData()
    }

    func showTrialWarning(remaining: Int) {
        self.remainingQueries = remaining
        // TODO: Could show a less intrusive notification for warnings
    }
    
    // MARK: - Pricing Data
    
    func fetchPricingData() {
        print("🔄 Fetching pricing data...")
        Task {
            do {
                let response = try await APIClient.shared.getPricing()
                print("✅ Received pricing response: \(response)")
                
                DispatchQueue.main.async {
                    // Send pricing data to JavaScript
                    do {
                        let jsonData = try JSONEncoder().encode(response.data)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            print("📤 Sending pricing data to JS: \(jsonString)")
                            let script = "setPricingData(\(jsonString));"
                            self.upgradeWebView?.evaluateJavaScript(script) { result, error in
                                if let error = error {
                                    print("❌ Failed to execute JS: \(error)")
                                } else {
                                    print("✅ Successfully sent pricing data to JS")
                                }
                            }
                        } else {
                            print("❌ Failed to convert JSON data to string")
                        }
                    } catch {
                        print("❌ Failed to encode pricing data: \(error)")
                    }
                }
            } catch {
                print("❌ Failed to fetch pricing: \(error)")
                DispatchQueue.main.async {
                    let script = "showError('Failed to load pricing options. Please try again.');"
                    self.upgradeWebView?.evaluateJavaScript(script)
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension UpgradeWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inject system appearance
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let script = "setSystemAppearance('\(isDarkMode ? "dark" : "light")')"
        webView.evaluateJavaScript(script)
    }
}

// MARK: - Message Handler

private final class UpgradeMessageHandler: NSObject, @preconcurrency WKScriptMessageHandler {
    weak var windowController: UpgradeWindowController?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }
        
        Task { @MainActor in
            switch action {
            case "fetchPricing":
                self.windowController?.fetchPricingData()
                
            case "upgrade":
                if let priceId = body["priceId"] as? String {
                    self.handleUpgrade(priceId: priceId)
                }
                
            case "cancel":
                self.windowController?.window?.close()
                
            case "getAppImages":
                self.sendAppImages()
                
            default:
                print("Unknown upgrade action: \(action)")
            }
        }
    }
    
    private func handleUpgrade(priceId: String) {
        Task {
            do {
                let response = try await APIClient.shared.createCheckoutSession(priceId: priceId)
                
                // Open Stripe checkout in browser
                if let url = URL(string: response.data.checkout_url) {
                    NSWorkspace.shared.open(url)
                }
                
                // Close the upgrade window
                DispatchQueue.main.async {
                    self.windowController?.window?.close()
                }
            } catch {
                // Show error in webview
                DispatchQueue.main.async { [weak self] in
                    guard let windowController = self?.windowController,
                          let webView = windowController.upgradeWebView else { return }
                    let script = "showError('Checkout failed. Please try again.');"
                    webView.evaluateJavaScript(script)
                }
            }
        }
    }
    
    private func sendAppImages() {
        var iconBase64: String? = nil
        var logoBase64: String? = nil
        
        // Load app icon
        if let appIcon = NSImage(named: "AppIcon") {
            iconBase64 = appIcon.base64String()
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let icon = NSImage(contentsOf: iconURL) {
            iconBase64 = icon.base64String()
        }
        
        // Load TheQuickFox logo
        if let logoImage = NSImage(named: "TheQuickFoxLogo") {
            logoBase64 = logoImage.base64String()
        } else if let logoURL = Bundle.main.url(forResource: "TheQuickFoxLogo", withExtension: "png"),
                  let logo = NSImage(contentsOf: logoURL) {
            logoBase64 = logo.base64String()
        }
        
        // Send to JavaScript
        DispatchQueue.main.async { [weak self] in
            guard let windowController = self?.windowController,
                  let webView = windowController.upgradeWebView else { return }
                  
            let iconJS = iconBase64 != nil ? "'\(iconBase64!)'" : "null"
            let logoJS = logoBase64 != nil ? "'\(logoBase64!)'" : "null"
            let script = "setAppImages(\(iconJS), \(logoJS));"
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ Failed to send app images: \(error)")
                } else {
                    print("✅ Successfully sent app images to JS")
                }
            }
        }
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func base64String() -> String? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        
        let pngData = bitmap.representation(using: .png, properties: [:])
        return pngData?.base64EncodedString()
    }
}
