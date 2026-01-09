//
//  HUDReducer.swift
//  TheQuickFox
//
//  Pure functions for HUD state transitions
//

import Foundation

func hudReducer(_ state: HUDState, _ action: HUDAction) -> HUDState {
    var newState = state

    switch action {
    // Window Management
    case .prepareWindow:
        // Prepare for showing but don't make visible yet
        break

    case .showWindow:
        // Actually show the HUD window
        newState.isVisible = true
        // Always enable rainbow border when HUD is visible (lightweight GPU animation)
        newState.ui.borderAnimationActive = true

    case .hide:
        newState.isVisible = false
        newState.ui.borderAnimationActive = false
        
    case .hideForReactivation:
        // Hide without cleaning up border animation state
        newState.isVisible = false

    case .hideWithReason:
        // Same as hide, but with close reason (handled in AppReducer)
        newState.isVisible = false
        newState.ui.borderAnimationActive = false

    case .animateToHUD:
        newState.ui.shouldAnimateToHUD = true

    // Mode and Settings
    case .changeMode(let mode):
        newState.mode = mode
        // Reset UI state when changing modes
        if mode == .compose {
            newState.ui.panelHeight = 224  // 160 + 64 for icon overflow
            newState.ui.responseContainerIsVisible = false
        }
        // Persist mode preference for next session
        UserPreferences.shared.saveMode(mode)

    case .changeTone(let tone):
        newState.tone = tone
        // Persist tone preference for next session
        UserPreferences.shared.saveTone(tone)

    // Query Processing
    case .updateQuery(let query):
        newState.currentQuery = query

    case .submitQuery(let query):
        newState.currentQuery = query
        newState.ui.textIsEditable = false
        newState.response = .idle
        newState.processing = .starting

    case .clearQuery:
        newState.currentQuery = ""

    // Response Handling
    case .startProcessing(let query, let screenshot):
        newState.currentQuery = query
        newState.processing = .active(pipeline: ProcessingInfo(
            query: query,
            startTime: Date(),
            screenshot: screenshot
        ))
        newState.response = .idle
        newState.groundingMetadata = nil  // Clear previous grounding data
        newState.ui.loaderIsVisible = true
        newState.ui.textIsEditable = false

        // Clear text during processing for both modes
        // In ask mode, query will be restored when streaming starts
        newState.currentQuery = ""

    case .receiveResponseToken(let token):
        switch newState.response {
        case .idle:
            newState.response = .streaming(content: token)
        case .streaming(let content):
            newState.response = .streaming(content: content + token)
        default:
            break
        }

        // For ask mode, expand and show response container when first token arrives
        if newState.mode == .ask && !newState.ui.responseContainerIsVisible {
            newState.ui.panelHeight = 384  // 320 + 64 for icon overflow
            newState.ui.responseContainerIsVisible = true
            newState.ui.loaderIsVisible = false

            // Restore the original query when streaming starts
            if case .active(let pipeline) = newState.processing {
                newState.currentQuery = pipeline.query
            }
        }

    case .receiveGroundingMetadata(let metadata):
        // Store grounding metadata for later - don't insert links yet
        // Links will be inserted when streaming completes
        newState.groundingMetadata = metadata
        if let supports = metadata.groundingSupports {
            print("🔗 Received \(supports.count) grounding citations, will insert links when streaming completes")
        }

    case .completeProcessing(let query, let response):
        // Insert citation links into the final completed text if we have grounding metadata
        let finalResponse: String
        if let metadata = newState.groundingMetadata {
            finalResponse = insertCitations(into: response, metadata: metadata)
            print("✅ Inserted citation links into completed response")
        } else {
            finalResponse = response
        }

        newState.response = .completed(content: finalResponse)
        newState.processing = .idle
        newState.ui.loaderIsVisible = false

        if newState.mode == .ask {
            // In ask mode, keep expanded and allow new input
            newState.ui.panelHeight = 384  // 320 + 64 for icon overflow
            newState.ui.responseContainerIsVisible = true
            newState.ui.textIsEditable = true
            // Query was already restored when streaming started
        } else {
            // In respond mode, this will trigger insertion and close
            newState.ui.textIsEditable = true
        }

    case .failProcessing(let error):
        newState.response = .failed(error: error)
        
        // Restore the original query if we have it in processing info
        if case .active(let pipeline) = state.processing {
            newState.currentQuery = pipeline.query
        }
        
        newState.processing = .idle
        newState.ui.loaderIsVisible = false
        newState.ui.textIsEditable = true
        
        // Show response container so error is visible
        if newState.mode == .ask {
            newState.ui.responseContainerIsVisible = true
            newState.ui.panelHeight = 384  // 320 + 64 for icon overflow
        }

    // UI State (these are typically triggered by effects or UI logic)
    case .setLoaderVisible(let visible):
        newState.ui.loaderIsVisible = visible

    case .setResponseContainerVisible(let visible):
        newState.ui.responseContainerIsVisible = visible

    case .setPanelHeight(let height):
        newState.ui.panelHeight = height

    case .setTextEditable(let editable):
        newState.ui.textIsEditable = editable

    case .setBorderAnimation(let active):
        newState.ui.borderAnimationActive = active

    case .resetAnimateToHUD:
        newState.ui.shouldAnimateToHUD = false

    case .setCanRespond(let canRespond):
        newState.canRespond = canRespond

    case .markResponseUsed:
        // Track that response was used successfully (for session management)
        // The actual session state is handled in AppReducer
        break

    // Navigation (these will be handled by effects that update session state)
    case .navigateHistoryUp, .navigateHistoryDown, .restoreFromHistory, .saveDraft:
        // These actions don't directly modify HUD state
        // They're handled by session reducer and effects
        break

    // Active window monitoring (handled by effects)
    case .activeWindowChanged:
        // No state change - effects handler manages the reload logic
        break
    }

    return newState
}

// MARK: - Helper Functions

/// Inserts citation markers into text based on grounding metadata
/// Returns the original text with inline citation numbers like [1][2] at the end of grounded segments
fileprivate func insertCitations(into content: String, metadata: GroundingMetadata) -> String {
    guard let supports = metadata.groundingSupports, !supports.isEmpty else {
        return content
    }

    // Debug: Log the original content
    print("📄 ORIGINAL RESPONSE (first 500 chars):")
    print(content.prefix(500))
    print("📄 Total length: \(content.count)")
    print("")

    var modifiedContent = content

    // Build URL to citation number mapping
    var urlToCitation: [String: Int] = [:]
    var citationCounter = 1

    // First pass: assign citation numbers to unique URLs
    for support in supports {
        let urls = support.groundingChunkIndices.compactMap { chunkIndex -> String? in
            guard let chunks = metadata.groundingChunks,
                  chunkIndex >= 0,
                  chunkIndex < chunks.count else {
                return nil
            }
            return chunks[chunkIndex].web?.uri
        }

        for url in urls {
            if urlToCitation[url] == nil {
                urlToCitation[url] = citationCounter
                citationCounter += 1
            }
        }
    }

    // Sort by startIndex in REVERSE order so we work backwards
    // This way, later insertions don't affect earlier indices
    let sortedSupports = supports.sorted { $0.segment.startIndex > $1.segment.startIndex }

    print("🔗 GROUNDING SEGMENTS (\(supports.count) total), \(urlToCitation.count) unique sources:")

    for support in sortedSupports {
        let segment = support.segment

        // Working backwards, so use original indices directly
        let segmentStart = segment.startIndex
        let segmentEnd = segment.endIndex

        // Validate indices
        guard segmentStart >= 0,
              segmentEnd <= modifiedContent.count,
              segmentStart < segmentEnd else {
            print("⚠️ Invalid indices: [\(segmentStart)-\(segmentEnd)], content length=\(modifiedContent.count)")
            continue
        }

        // Extract the segment text
        let startIdx = modifiedContent.index(modifiedContent.startIndex, offsetBy: segmentStart)
        let endIdx = modifiedContent.index(modifiedContent.startIndex, offsetBy: segmentEnd)
        let segmentText = String(modifiedContent[startIdx..<endIdx])

        print("  [\(segmentStart)-\(segmentEnd)] -> '\(segmentText.prefix(60))...'")

        // Get URLs from grounding chunks
        let urls = support.groundingChunkIndices.compactMap { chunkIndex -> String? in
            guard let chunks = metadata.groundingChunks,
                  chunkIndex >= 0,
                  chunkIndex < chunks.count else {
                return nil
            }
            return chunks[chunkIndex].web?.uri
        }

        guard !urls.isEmpty else {
            print("     ⚠️ No URLs, skipping")
            continue
        }

        // Get citation numbers for all URLs in this segment
        let citations = urls.compactMap { url -> Int? in
            return urlToCitation[url]
        }

        guard !citations.isEmpty else {
            print("     ⚠️ No citations found, skipping")
            continue
        }

        // Create citation markers like [1][2][3]
        let citationMarkers = citations.map { "[\($0)]" }.joined()

        // Insert citation at the END of the segment (endIdx is already a String.Index)
        modifiedContent.insert(contentsOf: citationMarkers, at: endIdx)
        print("     ✅ Added citations: \(citationMarkers)")
    }

    // Add sources section at the bottom
    if !urlToCitation.isEmpty {
        // Sort by citation number
        let sortedSources = urlToCitation.sorted { $0.value < $1.value }

        var sourcesSection = "\n\n---\n\n**Sources:**\n\n"
        for (url, number) in sortedSources {
            // Extract domain for display text
            let displayText = extractDomain(from: url) ?? "Source \(number)"
            sourcesSection += "[\(number)] [\(displayText)](\(url))\n\n"
        }

        modifiedContent += sourcesSection
        print("\n📚 Added \(sortedSources.count) sources at bottom")
    }

    return modifiedContent
}

/// Extract a readable domain name from a URL for display
fileprivate func extractDomain(from urlString: String) -> String? {
    guard let url = URL(string: urlString),
          let host = url.host else {
        return nil
    }

    // Remove www. prefix if present
    let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    return domain
}

extension HUDState {
    var shouldShowLoader: Bool {
        return processing != .idle && response == .idle
    }

    var shouldShowResponseContainer: Bool {
        switch response {
        case .streaming, .completed:
            return mode == .ask
        default:
            return false
        }
    }

    var shouldExpandPanel: Bool {
        return mode == .ask && shouldShowResponseContainer
    }
}
