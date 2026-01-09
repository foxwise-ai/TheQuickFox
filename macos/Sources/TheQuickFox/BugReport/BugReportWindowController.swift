//
//  BugReportWindowController.swift
//  TheQuickFox
//
//  Window controller for bug reporting with debug log upload
//

import Cocoa
import Foundation
import Compression

@MainActor
final class BugReportWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    private var bugReportCompletion: ((Bool) -> Void)?
    private var debugLogs: String?
    private var debugLogsData: Data?

    // UI Elements
    private var descriptionTextView: NSTextView!
    private var contactTextField: NSTextField!
    private var includeLogsCheckbox: NSButton!
    private var previewButton: NSButton!
    private var submitButton: NSButton!
    private var cancelButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var previewScrollView: NSScrollView!
    private var previewTextView: NSTextView!
    private var messageContainerView: NSView!
    private var messageLabel: NSTextField!
    private var messageIconView: NSTextField!

    // MARK: - Initialization

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Report Bug"
        window.center()

        self.init(window: window)
        window.delegate = self

        setupUI()
        loadDebugLogs()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Setup

    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        // Create main container
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        // Title
        let titleLabel = NSTextField(labelWithString: "Report a Bug")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Describe the issue you encountered. Debug logs can be included to help diagnose the problem.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.usesSingleLineMode = false
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(subtitleLabel)

        // Bug description label
        let descriptionLabel = NSTextField(labelWithString: "Bug Description:")
        descriptionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(descriptionLabel)

        // Bug description text view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .lineBorder
        scrollView.autohidesScrollers = false

        descriptionTextView = NSTextView()
        descriptionTextView.font = NSFont.systemFont(ofSize: 13)
        descriptionTextView.isRichText = false
        descriptionTextView.string = ""
        descriptionTextView.isAutomaticQuoteSubstitutionEnabled = false
        descriptionTextView.isAutomaticDashSubstitutionEnabled = false
        descriptionTextView.isAutomaticTextReplacementEnabled = false
        descriptionTextView.textContainer?.widthTracksTextView = true
        descriptionTextView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = descriptionTextView
        containerView.addSubview(scrollView)

        // Contact info label
        let contactLabel = NSTextField(labelWithString: "Email:")
        contactLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contactLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contactLabel)

        // Contact text field
        contactTextField = NSTextField()
        contactTextField.placeholderString = "your.email@example.com (required so we can follow up)"
        contactTextField.font = NSFont.systemFont(ofSize: 13)
        contactTextField.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contactTextField)

        // Include logs checkbox
        includeLogsCheckbox = NSButton(checkboxWithTitle: "Include debug logs (last 24 hours)", target: self, action: #selector(includeLogsToggled))
        includeLogsCheckbox.state = .on
        includeLogsCheckbox.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(includeLogsCheckbox)

        // Preview button
        previewButton = NSButton(title: "Preview Debug Data", target: self, action: #selector(previewDebugData))
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(previewButton)

        // Preview scroll view (initially hidden)
        previewScrollView = NSScrollView()
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = false
        previewScrollView.borderType = .lineBorder
        previewScrollView.autohidesScrollers = false
        previewScrollView.isHidden = true

        previewTextView = NSTextView()
        previewTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        previewTextView.isRichText = false
        previewTextView.isEditable = false
        previewTextView.textColor = .secondaryLabelColor
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.textContainer?.containerSize = NSSize(width: previewScrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        previewScrollView.documentView = previewTextView
        containerView.addSubview(previewScrollView)

        // Message container (for success/error messages)
        messageContainerView = NSView()
        messageContainerView.translatesAutoresizingMaskIntoConstraints = false
        messageContainerView.wantsLayer = true
        messageContainerView.layer?.cornerRadius = 8
        messageContainerView.isHidden = true
        containerView.addSubview(messageContainerView)

        // Message icon
        messageIconView = NSTextField(labelWithString: "")
        messageIconView.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        messageIconView.translatesAutoresizingMaskIntoConstraints = false
        messageContainerView.addSubview(messageIconView)

        // Message label
        messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        messageLabel.isEditable = false
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.usesSingleLineMode = false
        messageLabel.maximumNumberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageContainerView.addSubview(messageLabel)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)

        // Progress indicator
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(progressIndicator)

        // Buttons
        let buttonStackView = NSStackView()
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = 12
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelBugReport))
        submitButton = NSButton(title: "Submit Bug Report", target: self, action: #selector(submitBugReport))
        submitButton.keyEquivalent = "\r"

        buttonStackView.addArrangedSubview(NSView()) // Spacer
        buttonStackView.addArrangedSubview(cancelButton)
        buttonStackView.addArrangedSubview(submitButton)

        containerView.addSubview(buttonStackView)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),

            // Description text view
            scrollView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 150),

            // Contact label
            contactLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 15),
            contactLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),

            // Contact text field
            contactTextField.topAnchor.constraint(equalTo: contactLabel.bottomAnchor, constant: 8),
            contactTextField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contactTextField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contactTextField.heightAnchor.constraint(equalToConstant: 24),

            // Include logs checkbox
            includeLogsCheckbox.topAnchor.constraint(equalTo: contactTextField.bottomAnchor, constant: 15),
            includeLogsCheckbox.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),

            // Preview button
            previewButton.centerYAnchor.constraint(equalTo: includeLogsCheckbox.centerYAnchor),
            previewButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Preview scroll view
            previewScrollView.topAnchor.constraint(equalTo: includeLogsCheckbox.bottomAnchor, constant: 15),
            previewScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            previewScrollView.heightAnchor.constraint(equalToConstant: 120),

            // Message container
            messageContainerView.topAnchor.constraint(equalTo: previewScrollView.bottomAnchor, constant: 15),
            messageContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            messageContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            messageContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            // Message icon
            messageIconView.leadingAnchor.constraint(equalTo: messageContainerView.leadingAnchor, constant: 15),
            messageIconView.topAnchor.constraint(equalTo: messageContainerView.topAnchor, constant: 15),

            // Message label
            messageLabel.leadingAnchor.constraint(equalTo: messageIconView.trailingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: messageContainerView.trailingAnchor, constant: -15),
            messageLabel.topAnchor.constraint(equalTo: messageContainerView.topAnchor, constant: 15),
            messageLabel.bottomAnchor.constraint(equalTo: messageContainerView.bottomAnchor, constant: -15),

            // Status and progress
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: messageContainerView.bottomAnchor, constant: 10),

            progressIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),

            // Button stack view
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            buttonStackView.heightAnchor.constraint(equalToConstant: 32)
        ])

        // Initial state
        updatePreviewButtonVisibility()
    }

    // MARK: - Debug Logs

    private func loadDebugLogs() {
        Task {
            statusLabel.stringValue = "Collecting debug information..."

            // Use LoggingSystem to export comprehensive logs for bug reports (all levels)
            let exportResult = await withCheckedContinuation { continuation in
                // Create comprehensive export options for bug reports
                let bugReportOptions = LogExportOptions(
                    format: .text,
                    filterConfig: LogFilterConfig(
                        minLevel: .debug,  // Include all levels: debug, info, warning, error
                        timeWindow: 86400, // Last 24 hours
                        maxEntries: 500,   // More entries for comprehensive debugging
                        relevanceThreshold: 0.1  // Lower threshold to include more entries
                    ),
                    includeSystemInfo: true,
                    includeSensitiveData: false, // Still keep user data private
                    compressOutput: false,
                    filename: nil
                )

                LogExportManager.shared.exportLogs(options: bugReportOptions) { result in
                    LoggingManager.shared.info(.ui, "Bug report log export result - success: \(result.success), entries: \(result.stats.entriesExported)")
                    continuation.resume(returning: result)
                }
            }

            let logsText = exportResult.success ? exportResult.shareableText : nil

            await MainActor.run {
                if let logsText = logsText {
                    // Add additional debugging context to the logs
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    let systemInfo = SystemInfo.current()

                    let enhancedLogs = """
                        ================================
                        Bug Report Generated: \(timestamp)
                        App Version: \(systemInfo.appVersion)
                        OS Version: \(systemInfo.osVersion)
                        Device: \(systemInfo.deviceModel)
                        Locale: \(systemInfo.locale)
                        Log Entries: \(exportResult.stats.entriesExported)
                        Time Range: Last 24 hours
                        ================================

                        \(logsText)
                        """

                    self.debugLogs = enhancedLogs

                    // Also create compressed data for upload
                    if let logsData = enhancedLogs.data(using: .utf8) {
                        self.debugLogsData = try? self.createZipData(fileName: "debug_logs.txt", fileData: logsData)
                    }

                    let stats = exportResult.stats
                    self.statusLabel.stringValue = "Debug logs ready (\(stats.entriesExported) entries, \(enhancedLogs.count) chars)"
                } else {
                    self.debugLogs = nil
                    self.debugLogsData = nil
                    self.statusLabel.stringValue = "Unable to collect debug logs"
                    self.includeLogsCheckbox.isEnabled = false
                }

                // Update preview button visibility after logs are loaded
                self.updatePreviewButtonVisibility()
            }
        }
    }

    private func createZipData(fileName: String, fileData: Data) throws -> Data {
        // Use Foundation's built-in compression APIs
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempZipFile = tempDirectory.appendingPathComponent("temp_debug_logs.zip")
        let tempTextFile = tempDirectory.appendingPathComponent(fileName)

        // Clean up any existing temp files
        try? FileManager.default.removeItem(at: tempZipFile)
        try? FileManager.default.removeItem(at: tempTextFile)

        do {
            // Write the text file to disk temporarily
            try fileData.write(to: tempTextFile)

            // Create ZIP using macOS system command (most reliable)
            let process = Process()
            process.launchPath = "/usr/bin/zip"
            process.arguments = ["-j", tempZipFile.path, tempTextFile.path]
            process.launch()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(domain: "ZipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
            }

            // Read the created ZIP file
            let zipData = try Data(contentsOf: tempZipFile)

            // Clean up temp files
            try? FileManager.default.removeItem(at: tempZipFile)
            try? FileManager.default.removeItem(at: tempTextFile)

            return zipData

        } catch {
            // Clean up temp files on error
            try? FileManager.default.removeItem(at: tempZipFile)
            try? FileManager.default.removeItem(at: tempTextFile)
            throw error
        }
    }

    // MARK: - Actions

    @objc private func includeLogsToggled() {
        updatePreviewButtonVisibility()
        if includeLogsCheckbox.state == .off {
            hidePreview()
        }
    }

    @objc private func previewDebugData() {
        LoggingManager.shared.info(.ui, "Preview button clicked - checkbox: \(includeLogsCheckbox.state == .on), has logs: \(debugLogs != nil)")
        guard includeLogsCheckbox.state == .on, let logs = debugLogs else {
            LoggingManager.shared.info(.ui, "Preview guard failed - checkbox: \(includeLogsCheckbox.state == .on), logs nil: \(debugLogs == nil)")
            return
        }

        if previewScrollView.isHidden {
            // Show preview with truncated logs
            let truncatedLogs = String(logs.prefix(3000))
            let additionalText = logs.count > 3000 ? "\n\n... (showing first 3000 characters, full logs will be sent)" : ""
            previewTextView.string = truncatedLogs + additionalText

            previewScrollView.isHidden = false
            previewButton.title = "Hide Preview"

            // Expand window height
            if let window = window {
                var frame = window.frame
                frame.size.height += 135
                frame.origin.y -= 135
                window.setFrame(frame, display: true, animate: true)
            }
        } else {
            hidePreview()
        }
    }

    private func hidePreview() {
        if !previewScrollView.isHidden {
            previewScrollView.isHidden = true
            previewButton.title = "Preview Debug Data"

            // Shrink window height
            if let window = window {
                var frame = window.frame
                frame.size.height -= 135
                frame.origin.y += 135
                window.setFrame(frame, display: true, animate: true)
            }
        }
    }

    private func updatePreviewButtonVisibility() {
        let shouldHide = includeLogsCheckbox.state == .off || debugLogs == nil
        LoggingManager.shared.info(.ui, "Updating preview button visibility - checkbox: \(includeLogsCheckbox.state == .on), has logs: \(debugLogs != nil), will hide: \(shouldHide)")
        previewButton.isHidden = shouldHide
    }

    @objc private func submitBugReport() {
        let description = descriptionTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = contactTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !description.isEmpty else {
            showErrorMessage("Please provide a description of the bug.")
            return
        }

        guard !contact.isEmpty else {
            showErrorMessage("Please provide contact information so we can follow up.")
            return
        }

        // Disable UI during submission
        setUIEnabled(false)
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Submitting bug report..."

        Task {
            do {
                // Combine description and contact info in the message
                let fullMessage = """
                Contact: \(contact)

                Description:
                \(description)
                """

                // Submit bug report
                let submission = BugReportSubmission.create(message: fullMessage)
                LoggingManager.shared.info(.ui, "Submitting bug report with message length: \(fullMessage.count)")
                let response = try await APIClient.shared.submitBugReport(submission)
                LoggingManager.shared.info(.ui, "Bug report submitted successfully, feedback_id: \(response.feedback_id ?? "nil")")

                // Upload logs if requested and available
                if includeLogsCheckbox.state == .on,
                   let logsData = debugLogsData,
                   let feedbackId = response.feedback_id {

                    statusLabel.stringValue = "Uploading debug logs..."
                    let _ = try await APIClient.shared.uploadLogFile(logsData, feedbackId: feedbackId)
                }

                await MainActor.run {
                    self.progressIndicator.stopAnimation(nil)
                    self.statusLabel.stringValue = ""
                    self.handleSubmissionSuccess()
                }

            } catch {
                await MainActor.run {
                    self.progressIndicator.stopAnimation(nil)
                    self.setUIEnabled(true)
                    self.statusLabel.stringValue = ""

                    let errorMessage: String
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .quotaExceeded:
                            errorMessage = "Upload quota exceeded. Please try again later."
                        case .networkError:
                            errorMessage = "Network error. Please check your connection and try again."
                        case .unauthorized:
                            errorMessage = "Authentication failed. Please restart the app and try again."
                        case .serverError(_):
                            errorMessage = "Unable to submit bug report due to a server issue. Please try again later."
                        default:
                            errorMessage = "Failed to submit bug report: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Failed to submit bug report: \(error.localizedDescription)"
                    }

                    self.showErrorMessage(errorMessage)
                }
            }
        }
    }

    @objc private func cancelBugReport() {
        handleClose(success: false)
    }

    // MARK: - Helper Methods

    private func setUIEnabled(_ enabled: Bool) {
        descriptionTextView.isEditable = enabled
        contactTextField.isEnabled = enabled
        includeLogsCheckbox.isEnabled = enabled && debugLogs != nil
        previewButton.isEnabled = enabled
        submitButton.isEnabled = enabled
        cancelButton.isEnabled = enabled
    }

    private func showSuccessMessage(_ message: String) {
        messageIconView.stringValue = "✅"
        messageIconView.textColor = .systemGreen
        messageLabel.stringValue = message
        messageLabel.textColor = .controlTextColor
        messageContainerView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
        messageContainerView.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
        messageContainerView.layer?.borderWidth = 1
        messageContainerView.isHidden = false

        // Animate in
        messageContainerView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            messageContainerView.animator().alphaValue = 1.0
        }
    }

    private func showErrorMessage(_ message: String) {
        messageIconView.stringValue = "❌"
        messageIconView.textColor = .systemRed
        messageLabel.stringValue = message
        messageLabel.textColor = .controlTextColor
        messageContainerView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
        messageContainerView.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.3).cgColor
        messageContainerView.layer?.borderWidth = 1
        messageContainerView.isHidden = false

        // Animate in
        messageContainerView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            messageContainerView.animator().alphaValue = 1.0
        }
    }

    private func hideMessage() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            messageContainerView.animator().alphaValue = 0
        }) {
            self.messageContainerView.isHidden = true
        }
    }

    private func handleSubmissionSuccess() {
        showSuccessMessage("Bug report submitted successfully! Thank you for helping us improve TheQuickFox.")

        // Change submit button to "Close" and enable it
        submitButton.title = "Close"
        submitButton.isEnabled = true
        submitButton.action = #selector(closeAfterSuccess)

        // Disable other form elements since submission is complete
        descriptionTextView.isEditable = false
        contactTextField.isEnabled = false
        includeLogsCheckbox.isEnabled = false
        previewButton.isEnabled = false
    }

    @objc private func closeAfterSuccess() {
        handleClose(success: true)
    }

    private func handleClose(success: Bool) {
        bugReportCompletion?(success)
        bugReportCompletion = nil
        window?.close()
    }


    // MARK: - Public Methods

    func showBugReport(completion: ((Bool) -> Void)? = nil) {
        self.bugReportCompletion = completion
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Focus on description text view
        window?.makeFirstResponder(descriptionTextView)

        // Set up text view delegate to hide messages when editing
        descriptionTextView.delegate = self
    }
}

// MARK: - NSTextViewDelegate

extension BugReportWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        // Hide any error/success messages when user starts editing
        if !messageContainerView.isHidden {
            hideMessage()
        }
    }
}

// MARK: - NSWindowDelegate

extension BugReportWindowController {
    func windowWillClose(_ notification: Notification) {
        bugReportCompletion?(false)
        bugReportCompletion = nil
    }
}
