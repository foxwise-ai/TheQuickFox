//
//  HistoryWindowController.swift
//  TheQuickFox
//
//  Manages the history window with split view: list of entries on left,
//  query/response details on right
//

import Cocoa
import Combine
import Foundation

/// Window controller for the history viewer
class HistoryWindowController: NSWindowController {
    static let shared = HistoryWindowController()

    // MARK: - UI Components
    private var splitView: NSSplitView!
    private var historyTableView: NSTableView!
    private var queryTextView: NSTextView!
    private var responseTextView: NSTextView!
    private var historyScrollView: NSScrollView!
    private var queryScrollView: NSScrollView!
    private var responseScrollView: NSScrollView!

    // MARK: - Data
    private let historyManager = HistoryManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var selectedEntry: HistoryEntry? {
        didSet {
            updateDetailViews()
        }
    }

    private init() {
        // Create the window with custom window class for key handling
        let window = HistoryWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1000, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        setupWindow()
        setupViews()
        setupConstraints()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Setup

    private func setupWindow() {
        guard let window = window else { return }

        window.title = "TheQuickFox History"
        window.minSize = NSSize(width: 600, height: 400)
        window.center()

        // Set window level to normal (not floating like HUD)
        window.level = .normal

        // Enable standard window behaviors
        window.isReleasedWhenClosed = false  // Keep controller alive

        // Add keyboard shortcuts
        setupKeyboardShortcuts()
    }

    private func setupKeyboardShortcuts() {
        guard let window = window as? HistoryWindow else { return }

        // Set up the window to handle keyboard shortcuts
        window.historyController = self
    }

    @objc func closeWindow() {
        window?.close()
    }

    private func setupViews() {
        guard let window = window else { return }

        // Create split view
        splitView = NSSplitView()
        splitView.dividerStyle = .thin
        splitView.isVertical = true
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.delegate = self

        // Setup history list (left side)
        setupHistoryList()

        // Setup detail view (right side)
        setupDetailView()

        // Add to split view
        splitView.addArrangedSubview(historyScrollView)
        splitView.addArrangedSubview(createDetailContainer())

        // We'll set proportions in the delegate methods instead

        window.contentView = splitView
    }

    private func setupHistoryList() {
        // Create table view
        historyTableView = NSTableView()
        historyTableView.dataSource = self
        historyTableView.delegate = self
        historyTableView.allowsEmptySelection = true
        historyTableView.allowsMultipleSelection = false
        historyTableView.usesAlternatingRowBackgroundColors = true
        historyTableView.rowSizeStyle = .medium

        // Add single title column that takes full width
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "History"
        titleColumn.minWidth = 200
        titleColumn.resizingMask = .autoresizingMask
        historyTableView.addTableColumn(titleColumn)

        // Hide table header
        historyTableView.headerView = nil

        // Create scroll view
        historyScrollView = NSScrollView()
        historyScrollView.documentView = historyTableView
        historyScrollView.hasVerticalScroller = true
        historyScrollView.hasHorizontalScroller = false
        historyScrollView.autohidesScrollers = true
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupDetailView() {
        // Create query scroll view first
        queryScrollView = NSScrollView()
        queryScrollView.hasVerticalScroller = true
        queryScrollView.hasHorizontalScroller = false
        queryScrollView.autohidesScrollers = true
        queryScrollView.translatesAutoresizingMaskIntoConstraints = false
        queryScrollView.borderType = .noBorder

        // Create query text view and configure for wrapping
        queryTextView = NSTextView()
        queryTextView.isEditable = false
        queryTextView.isSelectable = true
        queryTextView.font = NSFont.systemFont(ofSize: 13)
        queryTextView.textColor = .labelColor
        queryTextView.backgroundColor = .controlBackgroundColor
        queryTextView.isRichText = false
        queryTextView.importsGraphics = false
        queryTextView.isVerticallyResizable = true
        queryTextView.isHorizontallyResizable = false
        queryTextView.autoresizingMask = [.width]

        // Set up text container for proper wrapping
        if let textContainer = queryTextView.textContainer {
            textContainer.containerSize = NSSize(
                width: queryScrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
        }

        queryScrollView.documentView = queryTextView

        // Create response scroll view
        responseScrollView = NSScrollView()
        responseScrollView.hasVerticalScroller = true
        responseScrollView.hasHorizontalScroller = false
        responseScrollView.autohidesScrollers = true
        responseScrollView.translatesAutoresizingMaskIntoConstraints = false
        responseScrollView.borderType = .noBorder

        // Create response text view and configure for wrapping
        responseTextView = NSTextView()
        responseTextView.isEditable = false
        responseTextView.isSelectable = true
        responseTextView.font = NSFont.systemFont(ofSize: 13)
        responseTextView.textColor = .labelColor
        responseTextView.backgroundColor = .textBackgroundColor
        responseTextView.isRichText = false
        responseTextView.importsGraphics = false
        responseTextView.isVerticallyResizable = true
        responseTextView.isHorizontallyResizable = false
        responseTextView.autoresizingMask = [.width]

        // Set up text container for proper wrapping
        if let textContainer = responseTextView.textContainer {
            textContainer.containerSize = NSSize(
                width: responseScrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
        }

        responseScrollView.documentView = responseTextView
    }

    private func createDetailContainer() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Create labels
        let queryLabel = NSTextField(labelWithString: "Query:")
        queryLabel.font = NSFont.boldSystemFont(ofSize: 13)
        queryLabel.translatesAutoresizingMaskIntoConstraints = false

        let responseLabel = NSTextField(labelWithString: "Response:")
        responseLabel.font = NSFont.boldSystemFont(ofSize: 13)
        responseLabel.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        container.addSubview(queryLabel)
        container.addSubview(queryScrollView)
        container.addSubview(responseLabel)
        container.addSubview(responseScrollView)

        // Setup constraints for detail container
        NSLayoutConstraint.activate([
            // Query label
            queryLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            queryLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            queryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            // Query scroll view
            queryScrollView.topAnchor.constraint(equalTo: queryLabel.bottomAnchor, constant: 8),
            queryScrollView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: 16),
            queryScrollView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -16),
            queryScrollView.heightAnchor.constraint(
                equalTo: container.heightAnchor, multiplier: 0.35),

            // Response label
            responseLabel.topAnchor.constraint(equalTo: queryScrollView.bottomAnchor, constant: 16),
            responseLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            responseLabel.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -16),

            // Response scroll view
            responseScrollView.topAnchor.constraint(
                equalTo: responseLabel.bottomAnchor, constant: 8),
            responseScrollView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: 16),
            responseScrollView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -16),
            responseScrollView.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -16),
        ])

        return container
    }

    private func setupConstraints() {
        guard let window = window else { return }

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
    }

    private func setupBindings() {
        // Listen for history updates
        historyManager.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.historyTableView.reloadData()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Interface

    func showWindow() {
        guard let window = window else { return }

        // Bring window to front and make it key
        window.makeKeyAndOrderFront(nil)
        window.center()

        // Ensure window appears above other windows
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()

        // Set split proportions after window is shown
        DispatchQueue.main.async {
            self.splitView.setPosition(300, ofDividerAt: 0)
        }

        // Reload data when window is shown
        historyTableView.reloadData()

        // Select first entry if available
        if historyManager.entries.count > 0 {
            historyTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            selectedEntry = historyManager.entries[0]
        }
    }

    private func updateDetailViews() {
        guard let entry = selectedEntry else {
            queryTextView.string = "Select a history entry to view details"
            responseTextView.string = ""
            return
        }

        // Update text container sizes to current scroll view width
        updateTextContainerSizes()

        // Add date and mode info to query view
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateString = formatter.string(from: entry.timestamp)
        let modeString = entry.mode == .ask ? "Ask" : "Compose"
        let toneString = entry.tone.rawValue.capitalized

        let queryHeader = "[\(dateString)] \(modeString) mode • \(toneString) tone\n\n"
        queryTextView.string = queryHeader + entry.query
        responseTextView.string = entry.response
    }

    private func updateTextContainerSizes() {
        // Update text container widths to match scroll view content width
        let queryWidth = queryScrollView.contentSize.width
        let responseWidth = responseScrollView.contentSize.width

        if let queryContainer = queryTextView.textContainer {
            queryContainer.containerSize = NSSize(
                width: queryWidth, height: CGFloat.greatestFiniteMagnitude)
        }

        if let responseContainer = responseTextView.textContainer {
            responseContainer.containerSize = NSSize(
                width: responseWidth, height: CGFloat.greatestFiniteMagnitude)
        }

        // Force layout update
        queryTextView.needsLayout = true
        responseTextView.needsLayout = true
        queryTextView.layoutManager?.ensureLayout(for: queryTextView.textContainer!)
        responseTextView.layoutManager?.ensureLayout(for: responseTextView.textContainer!)
    }
}

// MARK: - NSTableViewDataSource

extension HistoryWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return historyManager.entries.count
    }
}

// MARK: - NSTableViewDelegate

extension HistoryWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        guard row < historyManager.entries.count else { return nil }

        let entry = historyManager.entries[row]
        let identifier = tableColumn?.identifier

        if identifier == NSUserInterfaceItemIdentifier("title") {
            let cellView = NSTableCellView()

            let textField = NSTextField()
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            textField.font = NSFont.systemFont(ofSize: 13)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false

            // Show LLM-generated title or fallback
            textField.stringValue = entry.title

            // Add tooltip with date and query preview
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateString = formatter.string(from: entry.timestamp)
            let queryPreview = String(entry.query.prefix(100))
            textField.toolTip =
                "\(dateString)\n\nQuery: \(queryPreview)\(entry.query.count > 100 ? "..." : "")"

            cellView.addSubview(textField)
            cellView.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])

            return cellView
        }

        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = historyTableView.selectedRow
        if selectedRow >= 0 && selectedRow < historyManager.entries.count {
            selectedEntry = historyManager.entries[selectedRow]
        } else {
            selectedEntry = nil
        }
    }
}

// MARK: - NSSplitViewDelegate

extension HistoryWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false  // Prevent collapsing either side
    }

    func splitView(
        _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        return 200  // Minimum width for left panel
    }

    func splitView(
        _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        return splitView.bounds.width - 400  // Minimum 400px for right panel
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        // Custom resize behavior to maintain proportions
        let totalWidth = splitView.bounds.width
        let leftWidth = min(300, totalWidth * 0.3)  // 30% or 300px max
        let rightWidth = totalWidth - leftWidth - splitView.dividerThickness

        splitView.subviews[0].frame = NSRect(
            x: 0, y: 0, width: leftWidth, height: splitView.bounds.height)
        splitView.subviews[1].frame = NSRect(
            x: leftWidth + splitView.dividerThickness, y: 0, width: rightWidth,
            height: splitView.bounds.height)

        // Update text container sizes after resize
        DispatchQueue.main.async {
            self.updateTextContainerSizes()
        }
    }
}

// MARK: - Custom Window Class

/// Custom window class to handle keyboard shortcuts
class HistoryWindow: NSWindow {
    weak var historyController: HistoryWindowController?

    override func keyDown(with event: NSEvent) {
        // Handle Cmd+W to close window
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
            historyController?.closeWindow()
            return
        }

        super.keyDown(with: event)
    }
}
