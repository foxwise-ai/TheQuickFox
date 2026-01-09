//
//  HistoryReducer.swift
//  TheQuickFox
//
//  Pure functions for history state transitions
//

import Foundation

func historyReducer(_ state: HistoryState, _ action: HistoryAction) -> HistoryState {
    var newState = state

    switch action {
    case .addEntry(let entry):
        // Add new entry and update filtered list
        newState.entries.append(entry)
        newState.filteredEntries = filterEntries(newState.entries, searchQuery: newState.searchQuery)

    case .selectEntry(let entry):
        newState.selectedEntry = entry

    case .updateSearch(let query):
        newState.searchQuery = query
        newState.filteredEntries = filterEntries(newState.entries, searchQuery: query)

    case .deleteEntry(let id):
        newState.entries.removeAll { $0.id == id }
        newState.filteredEntries = filterEntries(newState.entries, searchQuery: newState.searchQuery)

        // Clear selection if deleted entry was selected
        if newState.selectedEntry?.id == id {
            newState.selectedEntry = nil
        }

    case .clearAll:
        newState.entries.removeAll()
        newState.filteredEntries.removeAll()
        newState.selectedEntry = nil

    case .updateEntryTitle(let id, let title):
        if let index = newState.entries.firstIndex(where: { $0.id == id }) {
            newState.entries[index].title = title
            newState.filteredEntries = filterEntries(newState.entries, searchQuery: newState.searchQuery)
        }
    }

    return newState
}

// MARK: - Helper Functions

private func filterEntries(_ entries: [HistoryEntry], searchQuery: String) -> [HistoryEntry] {
    guard !searchQuery.isEmpty else {
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    let query = searchQuery.lowercased()
    return entries.filter { entry in
        entry.title.lowercased().contains(query) ||
        entry.query.lowercased().contains(query) ||
        entry.response.lowercased().contains(query)
    }.sorted { $0.timestamp > $1.timestamp }
}
