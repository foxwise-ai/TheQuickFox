//
//  LoggingManager.swift
//  TheQuickFox
//
//  Centralised logging facade using Apple's unified logging system (OSLog).
//  Provides lightweight wrappers around `Logger` for the different stages of
//  prompt generation (screenshot capture, OCR, prompt composition, etc.).
//
//  Usage examples:
//
//      LoggingManager.shared.info(.screenshot, "Screenshot captured: \(pixels) px")
//
//      LoggingManager.shared.error(.ocr, "OCR failed: \(error)")
//
//  When the environment variable `TQF_DEV_LOG` is set, all log messages
//  are mirrored to stdout with emoji prefixes for quick inspection.
//
//  © 2025 TheQuickFox
//

import Foundation
import os

// MARK: – Categories

/// High-level logging domains used throughout the application.
public enum LogCategory: String {
    case screenshot = "screenshot"
    case ocr        = "ocr"
    case prompt     = "prompt"
    case pipeline   = "pipeline"
    case ui         = "ui"
    case generic    = "generic"
}

// MARK: – Logging Manager

public final class LoggingManager {

    // Singleton instance
    public static let shared = LoggingManager()

    // MARK: Private State

    /// Subsystem identifier for all TheQuickFox logs (appears in Console app).
    private let subsystem = "com.foxwiseai.thequickfox"

    /// When `true`, log messages are echoed to stdout (dev convenience).
    private let mirrorToStdout: Bool

    /// Lazily-instantiated `Logger`s per category.
    private var loggers: [LogCategory: Logger] = [:]

    /// Spin-lock protecting the loggers dictionary.
    private let lock = NSLock()

    private init() {
        mirrorToStdout = ProcessInfo.processInfo.environment["TQF_DEV_LOG"] != nil
    }

    // MARK: Public API

    /// General logging entry point.
    ///
    /// - Parameters:
    ///   - type:      OSLogType (default, info, debug, error, fault)
    ///   - category:  Logical logging domain.
    ///   - message:   Message producer (autoclosure for cheap evaluation).
    public func log(_ type: OSLogType = .default,
                    _ category: LogCategory = .generic,
                    _ message: @autoclosure () -> String) {
        let logger = self.logger(for: category)
        let msg = message()
        logger.log(level: type, "\(msg, privacy: .public)")

        if mirrorToStdout {
            let prefix: String
            switch type {
            case .info:  prefix = "ℹ️"
            case .debug: prefix = "🐛"
            case .error: prefix = "❗️"
            case .fault: prefix = "🔥"
            default:     prefix = "📝"
            }
            print("\(prefix) [\(category.rawValue)] \(msg)")
        }
    }

    // Convenience wrappers

    public func info(_ category: LogCategory = .generic,
                     _ message: @autoclosure () -> String) {
        log(.info, category, message())
    }

    public func debug(_ category: LogCategory = .generic,
                      _ message: @autoclosure () -> String) {
        log(.debug, category, message())
    }

    public func error(_ category: LogCategory = .generic,
                      _ message: @autoclosure () -> String) {
        log(.error, category, message())
    }

    // MARK: Private Helpers

    private func logger(for category: LogCategory) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[category] {
            return existing
        }
        let newLogger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = newLogger
        return newLogger
    }
}
