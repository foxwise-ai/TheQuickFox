//
//  AppCategoryDetector.swift
//  TheQuickFox
//
//  Detects whether the active application is a development/IDE app
//  to determine which tabs to show in the HUD.
//

import Foundation

enum AppCategoryDetector {

    /// Bundle ID patterns for development/IDE applications where users write code
    private static let developmentBundlePatterns = [
        // JetBrains IDEs
        "com.jetbrains.*",

        // Microsoft
        "com.microsoft.VSCode*",

        // Apple
        "com.apple.dt.Xcode",

        // Text editors
        "com.sublimetext.*",
        "com.github.atom",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "org.vim.MacVim",
        "com.qvacua.VimR",

        // Cursor
        "com.todesktop.cursor",
        "com.cursor.*",

        // Terminal applications
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "io.alacritty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",

        // Jupyter/notebooks
        "org.jupyter.*",

        // Database query tools (where you write SQL)
        "com.jetbrains.datagrip",
        "com.tableplus.TablePlus",
        "com.sequel-pro.sequel-pro",

        // Zed
        "dev.zed.Zed"
    ]

    /// Determines if the given app is a development/IDE application
    static func isDevelopmentApp(bundleID: String?, appName: String?) -> Bool {
        guard let bundleID = bundleID else { return false }

        // Check against patterns
        for pattern in developmentBundlePatterns {
            if pattern.hasSuffix("*") {
                let prefix = String(pattern.dropLast())
                if bundleID.hasPrefix(prefix) {
                    return true
                }
            } else if bundleID == pattern {
                return true
            }
        }

        return false
    }
}
