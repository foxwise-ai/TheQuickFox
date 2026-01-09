//
//  ToastManager.swift
//  TheQuickFox
//
//  Manages the insertion failure toast notification lifecycle
//

import Cocoa
import Combine

@MainActor
final class ToastManager {

    // MARK: - Singleton

    static let shared = ToastManager()

    // MARK: - Properties

    private var toast: InsertionFailureToast?
    private var cancellables = Set<AnyCancellable>()
    private let store = AppStore.shared

    // Current toast data
    private var currentResponseText: String = ""
    private var currentToastIdentifier: String = ""  // Track current toast to avoid re-animation

    // MARK: - Initialization

    private init() {
        setupBindings()
    }

    // MARK: - Bindings

    private func setupBindings() {
        store.toastStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] toastState in
                self?.updateToast(for: toastState)
            }
            .store(in: &cancellables)
    }

    // MARK: - Toast Management

    private func updateToast(for state: ToastState) {
        if state.isVisible {
            // Create identifier for this toast to detect if it's new content
            let toastIdentifier = "\(state.message)|\(state.errorDetail)|\(state.responseText)"

            // Only show/replace if this is a new toast (different content)
            if toastIdentifier != currentToastIdentifier {
                // Check if we're replacing an existing toast (2nd+ failure)
                let isReplacement = toast != nil

                // If a toast is already showing, dismiss it first
                if toast != nil {
                    print("🔄 Replacing existing toast with new failure - showing History hint")
                    toast?.dismiss()
                    toast = nil
                }

                // Show new toast with hint only if replacing
                showToast(
                    appIcon: state.appIcon,
                    appName: state.appName,
                    message: state.message,
                    errorDetail: state.errorDetail,
                    responseText: state.responseText,
                    hudFrame: state.hudFrame,
                    showHistoryHint: isReplacement
                )

                currentToastIdentifier = toastIdentifier
            } else {
                // Same toast content - just update stored response text for copy button
                currentResponseText = state.responseText
            }
        } else {
            hideToast()
            currentToastIdentifier = ""  // Reset identifier when hiding
        }
    }

    private func showToast(
        appIcon: NSImage?,
        appName: String,
        message: String,
        errorDetail: String,
        responseText: String,
        hudFrame: NSRect? = nil,
        showHistoryHint: Bool = false
    ) {
        // Store response text for copying
        currentResponseText = responseText

        // Dismiss existing toast if any
        toast?.dismiss()

        // Create new toast
        let newToast = InsertionFailureToast()

        newToast.configure(
            appIcon: appIcon,
            appName: appName,
            errorMessage: message,
            errorDetail: errorDetail,
            responseText: responseText,
            showHistoryHint: showHistoryHint
        )

        newToast.onCopy = { [weak self] in
            self?.handleCopy()
        }

        newToast.onClose = { [weak self] in
            self?.handleClose()
        }

        newToast.onOpenHistory = { [weak self] in
            self?.handleOpenHistory()
        }

        newToast.show(from: hudFrame)

        toast = newToast
    }

    private func hideToast() {
        toast?.dismiss()
        toast = nil
    }

    // MARK: - Actions

    private func handleCopy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentResponseText, forType: .string)

        print("✓ Response copied to clipboard")
    }

    private func handleClose() {
        // Dispatch action to hide toast
        store.dispatch(.toast(.hide))
    }

    private func handleOpenHistory() {
        // Open the History window
        Task { @MainActor in
            HistoryWindowController.shared.showWindow()
        }
    }
}
