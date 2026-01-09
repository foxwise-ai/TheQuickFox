//
//  ConcurrencyCompatibility.swift
//  TheQuickFox
//
//  Helper extensions that provide lightweight `@unchecked Sendable`
//  wrappers for common AppKit types that are routinely passed across
//  concurrency domains. These are safe in our contexts because the
//  objects are treated as immutable value-carriers once captured.
//
//  IMPORTANT:
//  - Only apply `@unchecked Sendable` when the captured instance is
//    NOT mutated after crossing an actor/queue boundary.
//  - Misuse can introduce data races. Review carefully.
//

import AppKit

// MARK: – NSImage

extension NSImage: @retroactive @unchecked Sendable { }

// MARK: – NSPasteboard

extension NSPasteboard: @retroactive @unchecked Sendable { }

// MARK: – NSAttributedString

extension NSAttributedString: @retroactive @unchecked Sendable { }

// MARK: – NSScreen

extension NSScreen: @retroactive @unchecked Sendable { }

// MARK: – Convenience boxed wrappers

/// Simple value box that carries a reference type across actors.
/// Use only when the wrapped reference will not be mutated.
public final class ImmutableBox<T>: @unchecked Sendable {
    public let value: T
    public init(_ value: T) { self.value = value }
}
