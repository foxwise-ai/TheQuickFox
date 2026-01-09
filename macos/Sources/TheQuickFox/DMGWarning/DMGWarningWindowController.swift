//
//  DMGWarningWindowController.swift
//  TheQuickFox
//
//  Displays a warning when the app is launched from a DMG,
//  with an option to move to Applications folder.
//

import AppKit
import Foundation

final class DMGWarningWindowController: NSWindowController {

    // MARK: - Properties

    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var messageLabel: NSTextField!
    private var moveButton: NSButton!
    private var quitButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!

    // MARK: - Initialization

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "TheQuickFox"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        contentView.wantsLayer = true

        // Icon
        iconImageView = NSImageView(frame: .zero)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown

        if let appIcon = NSImage(named: "AppIcon") {
            iconImageView.image = appIcon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let icon = NSImage(contentsOf: iconURL) {
            iconImageView.image = icon
        } else {
            iconImageView.image = NSImage(named: NSImage.applicationIconName)
        }

        contentView.addSubview(iconImageView)

        // Title
        titleLabel = NSTextField(labelWithString: "Move to Applications Folder")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        // Message
        let message = """
        TheQuickFox is running from a disk image. For the best experience and to avoid permission issues, please move it to your Applications folder.

        Click "Move to Applications" to automatically copy the app and restart.
        """

        messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        contentView.addSubview(messageLabel)

        // Progress indicator (hidden by default)
        progressIndicator = NSProgressIndicator(frame: .zero)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        contentView.addSubview(progressIndicator)

        // Status label (hidden by default)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true
        contentView.addSubview(statusLabel)

        // Move button
        moveButton = NSButton(title: "Move to Applications", target: self, action: #selector(moveToApplications))
        moveButton.translatesAutoresizingMaskIntoConstraints = false
        moveButton.bezelStyle = .rounded
        moveButton.keyEquivalent = "\r" // Enter key
        contentView.addSubview(moveButton)

        // Quit button
        quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.bezelStyle = .rounded
        quitButton.keyEquivalent = "\u{1b}" // Escape key
        contentView.addSubview(quitButton)

        // Layout
        NSLayoutConstraint.activate([
            // Icon
            iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            // Title
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Message
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Progress indicator
            progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressIndicator.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
            progressIndicator.widthAnchor.constraint(equalToConstant: 24),
            progressIndicator.heightAnchor.constraint(equalToConstant: 24),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Buttons
            moveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            moveButton.trailingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -8),
            moveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),

            quitButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            quitButton.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 8),
            quitButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    // MARK: - Public Methods

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions

    @objc private func moveToApplications() {
        // Show progress
        moveButton.isEnabled = false
        quitButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.isHidden = false
        statusLabel.stringValue = "Copying to Applications folder..."

        // Perform the move
        DMGLaunchDetector.moveToApplications { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)

                switch result {
                case .success:
                    self?.statusLabel.stringValue = "Launching from Applications..."
                    // Launch from Applications and quit
                    DMGLaunchDetector.launchFromApplicationsAndQuit()

                case .failure(let error):
                    self?.progressIndicator.isHidden = true
                    self?.moveButton.isEnabled = true
                    self?.quitButton.isEnabled = true
                    self?.statusLabel.stringValue = ""
                    self?.statusLabel.isHidden = true

                    // Show error alert
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func showError(_ error: DMGLaunchDetector.MoveError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Move Application"
        alert.informativeText = error.errorDescription ?? "An unknown error occurred."

        if case .destinationExists = error {
            alert.informativeText += "\n\nWould you like to replace the existing version?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Open Applications Folder")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Try again - the move function will handle removing the existing app
                moveToApplications()
            case .alertSecondButtonReturn:
                // Open Applications folder
                NSWorkspace.shared.open(URL(fileURLWithPath: DMGLaunchDetector.applicationsPath))
            default:
                break
            }
        } else {
            alert.addButton(withTitle: "Open Applications Folder")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: DMGLaunchDetector.applicationsPath))
            }
        }
    }
}
