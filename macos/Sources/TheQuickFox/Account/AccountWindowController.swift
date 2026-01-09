//
//  AccountWindowController.swift
//  TheQuickFox
//
//  Manages the account window for subscription info and API key management
//

import Cocoa
import SwiftUI
import Combine

// Custom window that can always become key (needed for accessory apps)
class AccountWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AccountWindowController: NSWindowController, NSWindowDelegate {
    
    static var shared: AccountWindowController?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.window?.delegate = self
    }
    
    func windowWillClose(_ notification: Notification) {
        // No need to change activation policy - we're always in regular mode
    }
    
    convenience init() {
        // Create a custom window that can properly become key
        let window = AccountWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Account Settings"
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        
        // Set delegate to handle window close
        window.delegate = self
        
        // Create SwiftUI view
        let contentView = AccountView(windowController: self)
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
        
        // Force the window to accept first responder
        window.makeFirstResponder(window)
        
        // Set minimum window size (increased for upgrade promo)
        window.minSize = NSSize(width: 500, height: 480)
        
        // IMPORTANT: This fixes the paste issue by ensuring the window accepts key events
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
    }
    
    static func show() {
        if shared == nil {
            shared = AccountWindowController()
        }

        // Refresh subscription data every time window is shown
        AppStore.shared.dispatch(.subscription(.startFetch))

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


// MARK: - Single-line NSTextField wrapper

struct SingleLineTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onEditingChanged: ((Bool) -> Void)?
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onEditingChanged: ((Bool) -> Void)?
        
        init(text: Binding<String>, onEditingChanged: ((Bool) -> Void)?) {
            self._text = text
            self.onEditingChanged = onEditingChanged
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            onEditingChanged?(true)
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            onEditingChanged?(false)
        }
    }
}

// MARK: - SwiftUI View

struct AccountView: View {
    @ObservedObject private var appStore = AppStore.shared
    @State private var isLoading: Bool = true

    weak var windowController: AccountWindowController?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
                
                Text("Account Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 20)
            
            Divider()
            
            // Subscription Info
            VStack(alignment: .leading, spacing: 12) {
                Text("Subscription Status")
                    .font(.headline)
                
                HStack {
                    Image(systemName: subscriptionIcon)
                        .foregroundColor(subscriptionColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscriptionTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(subscriptionDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()

                    // Manage Subscription button for active subscribers
                    if appStore.subscriptionState.hasActiveSubscription {
                        Button("Manage Subscription") {
                            openStripePortal()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // Upgrade Promotion Section (only for trial users)
            if !appStore.subscriptionState.hasActiveSubscription {
                VStack(alignment: .center, spacing: 16) {
                    // Gradient background box
                    ZStack {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.8),
                                Color.blue.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .cornerRadius(12)
                        
                        VStack(spacing: 16) {
                            Text("🚀 Upgrade to Premium")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Unlock unlimited AI-powered responses with flexible pricing options")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                            
                            HStack(spacing: 20) {
                                Text("✨ Monthly & yearly plans")
                                Text("💰 Flexible pricing")
                            }
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))
                            
                            Button(action: {
                                // Open upgrade window
                                UpgradeWindowController.shared.showUpgradePrompt()
                                windowController?.window?.close()
                            }) {
                                Text("See Plans & Pricing")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(20)
                    }
                    .frame(height: 200)
                    
                    Text("Only \(appStore.subscriptionState.trialQueriesRemaining) trial queries left")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .frame(width: 600, height: 480)
        .onAppear {
            // Dispatch subscription fetch to get fresh data
            appStore.dispatch(.subscription(.startFetch))
        }
    }
    
    // MARK: - Computed Properties
    
    private var subscriptionIcon: String {
        if appStore.subscriptionState.hasActiveSubscription {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }

    private var subscriptionColor: Color {
        if appStore.subscriptionState.hasActiveSubscription {
            return .green
        } else {
            return .orange
        }
    }

    private var subscriptionTitle: String {
        if appStore.subscriptionState.hasActiveSubscription {
            return "Premium Subscription"
        } else {
            return "Trial Account"
        }
    }
    
    private var subscriptionDescription: String {
        return formattedSubscriptionInfo
    }
    
    /// Get formatted subscription description from state
    private var formattedSubscriptionInfo: String {
        guard let details = appStore.subscriptionState.subscriptionDetails else {
            return appStore.subscriptionState.hasActiveSubscription ? "Active subscription" : ""
        }
        
        switch details.type {
        case "subscription":
            if let interval = details.interval,
               let amount = details.amount,
               let currency = details.currency {
                let price = formatPrice(amount: amount, currency: currency)
                let period = interval == "month" ? "monthly" : "yearly"
                return "Unlimited queries • \(price)/\(period)"
            }
            return "Unlimited queries • Active subscription"
        case "trial":
            return "\(details.trial_queries_remaining ?? appStore.subscriptionState.trialQueriesRemaining) trial queries remaining"
        default:
            return ""
        }
    }
    
    private func formatPrice(amount: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        let dollars = Double(amount) / 100.0
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
    
    // MARK: - Methods

    private func openStripePortal() {
        Task {
            do {
                let portalUrl = try await APIClient.shared.createCustomerPortalSession()
                await MainActor.run {
                    if let url = URL(string: portalUrl) {
                        NSWorkspace.shared.open(url)
                        // Close the Account Settings window after opening portal
                        windowController?.window?.close()
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Unable to Open Subscription Management"
                    alert.informativeText = "Please try again later or contact support."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
}