//
//  NetworkMonitorWindowController.swift
//  TheQuickFox
//
//  Window controller for the network monitor - shows users exactly
//  what data is sent to and received from servers.
//  Inspired by Little Snitch for transparency and trust.
//

import Cocoa
import SwiftUI

// Custom window that can always become key (needed for accessory apps)
class NetworkMonitorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class NetworkMonitorWindowController: NSWindowController, NSWindowDelegate {

    static var shared: NetworkMonitorWindowController?

    override func awakeFromNib() {
        super.awakeFromNib()
        self.window?.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // Stop monitoring and clear data when window closes
        Task { @MainActor in
            NetworkMonitor.shared.stopMonitoring()
        }
    }

    convenience init() {
        let window = NetworkMonitorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Network Monitor"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        window.delegate = self

        // Create SwiftUI view
        let contentView = NetworkMonitorView()
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView

        // Set minimum window size
        window.minSize = NSSize(width: 700, height: 400)

        // Force the window to accept key events
        window.makeFirstResponder(window)
    }

    static func show() {
        if shared == nil {
            shared = NetworkMonitorWindowController()
        }

        // Start monitoring when window opens
        NetworkMonitor.shared.startMonitoring()

        // Activate app first
        NSApp.activate(ignoringOtherApps: true)

        // Ensure window comes to front
        DispatchQueue.main.async {
            shared?.window?.orderFrontRegardless()
            shared?.window?.makeKeyAndOrderFront(nil)
            shared?.window?.makeMain()
            shared?.window?.makeKey()
        }
    }
}

// MARK: - Main View

struct NetworkMonitorView: View {
    @ObservedObject private var monitor = NetworkMonitor.shared
    @State private var selectedRequest: NetworkRequestEntry?
    @State private var searchText = ""
    @State private var filterCategory: NetworkRequestEntry.RequestCategory?
    @State private var showOnlySavedToServer = false

    private var filteredRequests: [NetworkRequestEntry] {
        var results = monitor.requests

        if !searchText.isEmpty {
            results = results.filter { request in
                request.endpoint.localizedCaseInsensitiveContains(searchText) ||
                request.url.absoluteString.localizedCaseInsensitiveContains(searchText) ||
                request.requestBodySummary.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let category = filterCategory {
            results = results.filter { $0.category == category }
        }

        if showOnlySavedToServer {
            results = results.filter { $0.isSavedOnServer }
        }

        return results
    }

    var body: some View {
        HSplitView {
            // Left: Request list
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search requests...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)

                    // Category filter
                    Menu {
                        Button("All Categories") {
                            filterCategory = nil
                        }
                        Divider()
                        ForEach(NetworkRequestEntry.RequestCategory.allCases, id: \.self) { category in
                            Button {
                                filterCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filterCategory?.icon ?? "line.3.horizontal.decrease.circle")
                            Text(filterCategory?.rawValue ?? "All")
                        }
                        .frame(width: 130)
                    }
                    .menuStyle(.borderlessButton)

                    // Saved to server filter
                    Toggle(isOn: $showOnlySavedToServer) {
                        HStack(spacing: 4) {
                            Image(systemName: "externaldrive.badge.icloud")
                            Text("Saved")
                        }
                    }
                    .toggleStyle(.button)
                    .help("Show only requests that save data to server")

                    Spacer()
                }
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Request list
                if filteredRequests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(monitor.requests.isEmpty ? "No network activity yet" : "No matching requests")
                            .foregroundColor(.secondary)
                        if !monitor.requests.isEmpty {
                            Button("Clear Filters") {
                                searchText = ""
                                filterCategory = nil
                                showOnlySavedToServer = false
                            }
                        }

                        // Session-only note
                        if monitor.requests.isEmpty {
                            Text("Network activity will appear here as you use TheQuickFox")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RequestListView(
                        requests: filteredRequests,
                        selectedRequest: $selectedRequest
                    )
                }

                // Footer with session info
                Divider()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Recording - data clears when this window closes")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(minWidth: 350, maxWidth: 450)

            // Right: Detail view
            if let request = selectedRequest {
                RequestDetailView(request: request)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a request to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Request List View

struct RequestListView: View {
    let requests: [NetworkRequestEntry]
    @Binding var selectedRequest: NetworkRequestEntry?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(requests) { request in
                    RequestRowView(
                        request: request,
                        isSelected: selectedRequest?.id == request.id,
                        hasScreenshot: request.screenshotImage != nil
                    )
                    .onTapGesture {
                        selectedRequest = request
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Request Row View

struct RequestRowView: View {
    @ObservedObject var request: NetworkRequestEntry
    let isSelected: Bool
    let hasScreenshot: Bool

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
            categoryIcon
            mainContent
            statusCodeBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var statusIndicator: some View {
        StatusIndicator(status: request.status)
            .frame(width: 12, height: 12)
    }

    private var categoryIcon: some View {
        Image(systemName: request.category.icon)
            .foregroundColor(categoryColor)
            .frame(width: 16)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            headerRow
            Text(request.requestBodySummary)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var headerRow: some View {
        HStack {
            Text(request.endpoint)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            if hasScreenshot {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
            }

            if request.isSavedOnServer {
                Image(systemName: "externaldrive.badge.icloud")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            Spacer()

            if let time = request.responseTime {
                Text(formatTime(time))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusCodeBadge: some View {
        if let code = request.statusCode {
            Text("\(code)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(statusCodeColor(code))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusCodeColor(code).opacity(0.15))
                .cornerRadius(4)
        }
    }

    private var categoryColor: Color {
        switch request.category {
        case .authentication: return .blue
        case .aiCompose: return .purple
        case .usage: return .green
        case .analytics: return .orange
        case .billing: return .pink
        case .feedback: return .cyan
        case .other: return .gray
        }
    }

    private func statusCodeColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<500: return .red
        case 500...: return .red
        default: return .gray
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        if time < 1 {
            return String(format: "%.0fms", time * 1000)
        } else {
            return String(format: "%.1fs", time)
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: NetworkRequestEntry.RequestStatus
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(isAnimating ? 1.5 : 1)
                    .opacity(isAnimating ? 0 : 1)
            )
            .onAppear {
                if status == .inProgress {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }
            }
            .onChange(of: status) { newValue in
                if newValue == .inProgress {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                } else {
                    isAnimating = false
                }
            }
    }

    private var color: Color {
        switch status {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

// MARK: - Request Detail View

struct RequestDetailView: View {
    @ObservedObject var request: NetworkRequestEntry
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: request.category.icon)
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.endpoint)
                            .font(.headline)
                        Text(request.method + " " + request.url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    StatusBadge(status: request.status, statusCode: request.statusCode)
                }

                // Server save warning if applicable
                if request.isSavedOnServer {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.icloud")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Data Saved on Server")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let description = request.serverDataDescription {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Metadata row
                HStack(spacing: 16) {
                    MetadataItem(label: "Started", value: formatDate(request.startTime))
                    if let time = request.responseTime {
                        MetadataItem(label: "Duration", value: formatDuration(time))
                    }
                    if let size = request.responseSize {
                        MetadataItem(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Request").tag(0)
                Text("Response").tag(1)
                Text("Headers").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case 0:
                        RequestBodyView(request: request)
                    case 1:
                        ResponseBodyView(request: request)
                    case 2:
                        HeadersView(request: request)
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        if time < 1 {
            return String(format: "%.0f ms", time * 1000)
        } else {
            return String(format: "%.2f s", time)
        }
    }
}

// MARK: - Supporting Views

struct StatusBadge: View {
    let status: NetworkRequestEntry.RequestStatus
    let statusCode: Int?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.15))
        .cornerRadius(12)
    }

    private var statusText: String {
        if let code = statusCode {
            return "\(code) \(status.rawValue)"
        }
        return status.rawValue
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed:
            if let code = statusCode, code >= 400 {
                return .red
            }
            return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

struct MetadataItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct RequestBodyView: View {
    let request: NetworkRequestEntry
    @State private var showFullScreenshot = false
    @State private var showOCRData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request Summary")
                .font(.headline)

            Text(request.requestBodySummary)
                .foregroundColor(.secondary)

            // Screenshot preview if present
            if let screenshot = request.screenshotImage {
                Divider()

                Text("Screenshot Sent")
                    .font(.headline)

                Button(action: { showFullScreenshot = true }) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: screenshot)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                        // Expand hint
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(8)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to view full size")
                .sheet(isPresented: $showFullScreenshot) {
                    ScreenshotFullView(image: screenshot)
                }
            }

            // OCR data preview if present
            if let ocrData = request.ocrData {
                Divider()

                HStack {
                    Text("OCR Context Sent")
                        .font(.headline)
                    Spacer()
                    Text("\(ocrData.observations.count) text regions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: { showOCRData = true }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // Show preview of first few lines
                            let previewLines = ocrData.texts.components(separatedBy: "\n").prefix(3)
                            ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                            }
                            if ocrData.texts.components(separatedBy: "\n").count > 3 {
                                Text("...")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Click to view full OCR data")
                .sheet(isPresented: $showOCRData) {
                    OCRDataFullView(ocrData: ocrData)
                }
            }

            if request.requestBody != nil {
                Divider()

                Text("Raw Body")
                    .font(.headline)

                CodeBlock(content: request.formattedRequestBody)
            } else if request.screenshotImage == nil && request.ocrData == nil {
                Text("(No request body)")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

// Full-screen screenshot viewer
struct ScreenshotFullView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Screenshot Sent to API")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Image
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .frame(maxWidth: 1200, maxHeight: 900)
    }
}

// Full OCR data viewer
struct OCRDataFullView: View {
    let ocrData: OCRDisplayData
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OCR Context Sent to API")
                        .font(.headline)
                    Text("\(ocrData.observations.count) text regions detected in \(String(format: "%.0f", ocrData.latencyMs))ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Plain Text").tag(0)
                Text("Visual Layout").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch selectedTab {
            case 0:
                // Plain text view
                ScrollView {
                    Text(ocrData.texts)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))

            default:
                // Visual layout view
                OCRVisualLayoutView(observations: ocrData.observations)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .frame(maxWidth: 900, maxHeight: 800)
    }
}

// Visual layout showing text positions
struct OCRVisualLayoutView: View {
    let observations: [OCRDisplayData.Observation]
    @State private var hoveredIndex: Int? = nil

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color(NSColor.textBackgroundColor)

                    // Text regions
                    ForEach(Array(observations.enumerated()), id: \.offset) { index, obs in
                        if obs.quad != nil {
                            OCRRegionView(
                                observation: obs,
                                index: index,
                                containerSize: geometry.size,
                                isHovered: hoveredIndex == index
                            )
                            .onHover { hovering in
                                hoveredIndex = hovering ? index : nil
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 600)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct OCRRegionView: View {
    let observation: OCRDisplayData.Observation
    let index: Int
    let containerSize: CGSize
    let isHovered: Bool

    var body: some View {
        let quad = observation.quad!
        // Coordinates are already in top-left origin (flipped in TextRecognizer)
        let x = quad.topLeft.x * containerSize.width
        let y = quad.topLeft.y * containerSize.height
        let width = (quad.topRight.x - quad.topLeft.x) * containerSize.width
        let height = (quad.bottomLeft.y - quad.topLeft.y) * containerSize.height

        Text(observation.text)
            .font(.system(size: 11, design: .monospaced))
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isHovered ? Color.accentColor.opacity(0.3) : confidenceColor.opacity(0.2))
            .border(isHovered ? Color.accentColor : confidenceColor.opacity(0.6), width: isHovered ? 2 : 1)
            .position(x: x + max(width, 20) / 2, y: y + max(height, 12) / 2)
            .help("[\(index + 1)] \(observation.text) (\(Int(observation.confidence * 100))% confidence)")
    }

    private var confidenceColor: Color {
        if observation.confidence >= 0.9 {
            return .green
        } else if observation.confidence >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}

struct ResponseBodyView: View {
    let request: NetworkRequestEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = request.responseSummary {
                Text("Response Summary")
                    .font(.headline)

                Text(summary)
                    .foregroundColor(.secondary)

                Divider()
            }

            if request.status == .inProgress {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for response...")
                        .foregroundColor(.secondary)
                }
            } else if let error = request.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.secondary)
                }
            } else if request.responseBody != nil {
                Text("Response Body")
                    .font(.headline)

                CodeBlock(content: request.formattedResponseBody)
            } else {
                Text("(No response body)")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct HeadersView: View {
    let request: NetworkRequestEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Request headers
            VStack(alignment: .leading, spacing: 8) {
                Text("Request Headers")
                    .font(.headline)

                if request.requestHeaders.isEmpty {
                    Text("(No headers)")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(Array(request.requestHeaders.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HeaderRow(key: key, value: value)
                    }
                }
            }

            Divider()

            // Response headers
            VStack(alignment: .leading, spacing: 8) {
                Text("Response Headers")
                    .font(.headline)

                if let headers = request.responseHeaders, !headers.isEmpty {
                    ForEach(Array(headers.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HeaderRow(key: key, value: value)
                    }
                } else {
                    Text("(No response headers)")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }
}

struct HeaderRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .frame(width: 150, alignment: .trailing)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct CodeBlock: View {
    let content: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(content)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}
