import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Installing a document must keep the content storage's `NSTextStorage`, because
/// selection, copy and link clicks all still go through it on AppKit, while TextKit 2
/// draws from `attributedString` alone — so losing it renders perfectly and breaks
/// everything else (see ARCHITECTURE.md, "TextKit 2 traps").
@Suite("Storage install")
struct StorageInstallTests {
  private let text = NSAttributedString(string: "Section 1\nThe first paragraph.\n")

  @Test func `installing keeps the text storage`() {
    let storage = NSTextContentStorage()
    storage.install(text)
    #expect(storage.textStorage != nil)
    #expect(storage.textStorage?.string == text.string)
    #expect(storage.attributedString?.string == text.string)
  }

  @Test func `installing twice replaces the text and still keeps the storage`() {
    let storage = NSTextContentStorage()
    storage.install(text)
    storage.install(NSAttributedString(string: "Replaced.\n"))
    #expect(storage.textStorage?.string == "Replaced.\n")
  }

  /// The trap itself, pinned so the day the framework stops doing this is noticed:
  /// the obvious assignment leaves the text storage nil. If this starts failing,
  /// the rule may be retired — until then, `install` is the only way in.
  @Test func `assigning the attributed string discards the text storage`() {
    let storage = NSTextContentStorage()
    #expect(storage.textStorage != nil)
    storage.attributedString = text
    #expect(storage.textStorage == nil)
  }
}
