//
//  SimpleAccountWindow.swift
//  TheQuickFox
//
//  Simple native AppKit window for API key management
//

import Cocoa

class SimpleAccountWindow: NSWindow, NSWindowDelegate {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    
    private let apiKeyField = NSTextField()
    private let saveButton = NSButton()
    private let statusLabel = NSTextField()
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Account Settings"
        self.center()
        self.delegate = self
        
        setupUI()
        loadCurrentKey()
    }
    
    func windowWillClose(_ notification: Notification) {
        // No need to change activation policy - we're always in regular mode
    }
    
    private func setupUI() {
        let contentView = NSView()
        self.contentView = contentView
        
        // Title
        let titleLabel = NSTextField(labelWithString: "OpenAI API Key")
        titleLabel.font = .boldSystemFont(ofSize: 14)
        
        // Subscription info
        let subscriptionLabel = NSTextField(labelWithString: "Subscription Status")
        subscriptionLabel.font = .systemFont(ofSize: 12)
        subscriptionLabel.textColor = .secondaryLabelColor
        
        // API Key field
        apiKeyField.placeholderString = "sk-..."
        apiKeyField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        
        // Add paste button as workaround
        let pasteButton = NSButton()
        pasteButton.title = "Paste from Clipboard"
        pasteButton.bezelStyle = .rounded
        pasteButton.target = self
        pasteButton.action = #selector(pasteFromClipboard)
        
        // Save button
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveAPIKey)
        
        // Status label
        statusLabel.stringValue = ""
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.font = .systemFont(ofSize: 11)
        
        // Layout
        [titleLabel, subscriptionLabel, apiKeyField, pasteButton, saveButton, statusLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            subscriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            subscriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            apiKeyField.topAnchor.constraint(equalTo: subscriptionLabel.bottomAnchor, constant: 15),
            apiKeyField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            apiKeyField.widthAnchor.constraint(equalToConstant: 300),
            apiKeyField.heightAnchor.constraint(equalToConstant: 24),
            
            pasteButton.centerYAnchor.constraint(equalTo: apiKeyField.centerYAnchor),
            pasteButton.leadingAnchor.constraint(equalTo: apiKeyField.trailingAnchor, constant: 10),
            
            saveButton.centerYAnchor.constraint(equalTo: apiKeyField.centerYAnchor),
            saveButton.leadingAnchor.constraint(equalTo: pasteButton.trailingAnchor, constant: 10),
            saveButton.widthAnchor.constraint(equalToConstant: 80),
            
            statusLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }
    
    private func loadCurrentKey() {
        if let key = try? KeychainManager.shared.getUserOpenAIKey() {
            apiKeyField.stringValue = key
        }
    }
    
    @objc private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            apiKeyField.stringValue = string
            statusLabel.textColor = .systemBlue
            statusLabel.stringValue = "Pasted from clipboard"
        }
    }
    
    @objc private func saveAPIKey() {
        let key = apiKeyField.stringValue
        guard !key.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Please enter an API key"
            return
        }
        
        do {
            try KeychainManager.shared.saveUserOpenAIKey(key)
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = "API key saved successfully!"
            
            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.statusLabel.stringValue = ""
            }
        } catch {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Error saving API key: \(error.localizedDescription)"
        }
    }
    
    static func showWindow() {
        let window = SimpleAccountWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Focus the text field
        window.makeFirstResponder(window.apiKeyField)
    }
}