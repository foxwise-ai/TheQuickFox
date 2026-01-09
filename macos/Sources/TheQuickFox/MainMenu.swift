//
//  MainMenu.swift
//  TheQuickFox
//
//  Sets up the main menu bar with Edit menu for paste support
//  and provides shared menu item builders for dock/status bar menus
//

import Cocoa

// MARK: - Shared Menu Item Builders

/// Creates fox tail menu items that can be used in status bar, dock menu, and app menu
/// - Parameter includeKeyEquivalents: Whether to include keyboard shortcuts (false for dock menu)
/// - Returns: Array of NSMenuItems with the fox tail options
func createFoxTailMenuItems(includeKeyEquivalents: Bool = true) -> [NSMenuItem] {
    var items: [NSMenuItem] = []

    // Getting Started
    let onboardingItem = NSMenuItem(
        title: "Getting Started...",
        action: #selector(AppDelegate.showOnboarding),
        keyEquivalent: ""
    )
    if let icon = NSImage(systemSymbolName: "house", accessibilityDescription: nil) {
        onboardingItem.image = icon
    }
    items.append(onboardingItem)

    // Statistics
    let statsItem = NSMenuItem(
        title: "Statistics...",
        action: #selector(AppDelegate.showMetricsDashboard),
        keyEquivalent: includeKeyEquivalents ? "s" : ""
    )
    if let icon = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil) {
        statsItem.image = icon
    }
    items.append(statsItem)

    // Account Settings
    let accountItem = NSMenuItem(
        title: "Account Settings...",
        action: #selector(AppDelegate.showAccountSettings),
        keyEquivalent: includeKeyEquivalents ? "," : ""
    )
    if let icon = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil) {
        accountItem.image = icon
    }
    items.append(accountItem)

    items.append(NSMenuItem.separator())

    // Show History
    let historyItem = NSMenuItem(
        title: "Show History...",
        action: #selector(AppDelegate.showHistory),
        keyEquivalent: includeKeyEquivalents ? "h" : ""
    )
    if let icon = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: nil) {
        historyItem.image = icon
    }
    items.append(historyItem)

    // Network Monitor
    let networkItem = NSMenuItem(
        title: "Network Monitor...",
        action: #selector(AppDelegate.showNetworkMonitor),
        keyEquivalent: includeKeyEquivalents ? "n" : ""
    )
    if let icon = NSImage(systemSymbolName: "network", accessibilityDescription: nil) {
        networkItem.image = icon
    }
    items.append(networkItem)

    // Type Hints Toggle
    let typeHintsItem = NSMenuItem(
        title: "Type Hints",
        action: #selector(AppDelegate.toggleTypeHints(_:)),
        keyEquivalent: includeKeyEquivalents ? "t" : ""
    )
    if let icon = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil) {
        typeHintsItem.image = icon
    }
    // State will be updated by toggleTypeHints action; default to on
    typeHintsItem.state = .on
    items.append(typeHintsItem)

    items.append(NSMenuItem.separator())

    // Check for Updates
    let updateItem = NSMenuItem(
        title: "Check for Updates...",
        action: #selector(AppDelegate.checkForUpdates),
        keyEquivalent: ""
    )
    if let icon = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil) {
        updateItem.image = icon
    }
    items.append(updateItem)

    // Report Bug
    let bugItem = NSMenuItem(
        title: "Report Bug...",
        action: #selector(AppDelegate.reportBug),
        keyEquivalent: ""
    )
    if let icon = NSImage(systemSymbolName: "hand.thumbsdown", accessibilityDescription: nil) {
        bugItem.image = icon
    }
    items.append(bugItem)

    // About
    let aboutItem = NSMenuItem(
        title: "About TheQuickFox",
        action: #selector(AppDelegate.showAbout),
        keyEquivalent: ""
    )
    if let icon = NSImage(systemSymbolName: "signature", accessibilityDescription: nil) {
        aboutItem.image = icon
    }
    items.append(aboutItem)

    #if DEBUG
    items.append(NSMenuItem.separator())

    // Debug: Test Type Hint Toast
    let testHintItem = NSMenuItem(
        title: "Test Type Hint",
        action: #selector(AppDelegate.testTypeHint),
        keyEquivalent: ""
    )
    if let icon = NSImage(systemSymbolName: "ant", accessibilityDescription: nil) {
        testHintItem.image = icon
    }
    items.append(testHintItem)
    #endif

    return items
}

/// Creates a complete dock menu with all fox tail items
func createDockMenu() -> NSMenu {
    let menu = NSMenu()

    // Add all fox tail items (no keyboard shortcuts for dock menu)
    for item in createFoxTailMenuItems(includeKeyEquivalents: false) {
        menu.addItem(item)
    }

    // Note: Quit is automatically added by macOS to dock menus

    return menu
}

// MARK: - Main Menu Setup

func setupMainMenu() {
    let mainMenu = NSMenu()

    // Application menu with full fox tail items
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.title = "TheQuickFox"

    // Add all fox tail items to the app menu
    for item in createFoxTailMenuItems(includeKeyEquivalents: true) {
        appMenu.addItem(item)
    }

    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "Quit TheQuickFox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // Edit menu - THIS IS CRITICAL FOR PASTE TO WORK
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    NSApp.mainMenu = mainMenu
}
