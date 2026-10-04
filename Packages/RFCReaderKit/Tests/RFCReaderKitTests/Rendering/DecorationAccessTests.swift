import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Decoration access")
struct DecorationAccessTests {
  /// Prose, then a table whose label is bold and whose value is not, then prose:
  /// the table's decoration spans two storage runs, as a stacked table's does.
  private static func text() -> NSAttributedString {
    let text = NSMutableAttributedString(string: "Before\n")
    text.append(
      NSAttributedString(
        string: "Label ",
        attributes: [
          .rfcDecoration: RFCDecoration.table.rawValue,
          .font: PlatformFont.boldSystemFont(ofSize: 12),
        ]))
    text.append(
      NSAttributedString(
        string: "value\n",
        attributes: [
          .rfcDecoration: RFCDecoration.table.rawValue, .font: PlatformFont.systemFont(ofSize: 12),
        ]))
    text.append(NSAttributedString(string: "After"))
    return text
  }

  @Test func `a decoration's run is the whole block, across its storage runs`() {
    let text = Self.text()
    // In the regular value, after the bold label: `effectiveRange` names only the
    // value, and every line of the block drew its own card (the staircase).
    let run = text.decorationRun(at: 10)
    #expect(run?.decoration == .table)
    #expect(run?.range == NSRange(location: 7, length: 12))
  }

  @Test func `a decoration is read without walking its run`() {
    let text = Self.text()
    #expect(text.decoration(at: 7) == .table)
    #expect(text.decoration(at: 0) == nil)
    #expect(text.decoration(at: text.length - 1) == nil)
  }

  @Test func `undecorated text and offsets outside the text have no run`() {
    let text = Self.text()
    #expect(text.decorationRun(at: 2) == nil)
    #expect(text.decorationRun(at: -1) == nil)
    #expect(text.decorationRun(at: text.length) == nil)
    #expect(text.decoration(at: text.length) == nil)
  }

  @Test func `a box is equal to itself alone`() {
    let reference = CrossReference(target: .document(.rfc(9110), section: nil))
    let box = ReferenceBox(reference)
    // An `NSObject`, so `isEqual(_:)` is identity by definition rather than by how a
    // Swift class happens to bridge.
    #expect(box.isEqual(box))
    #expect(!box.isEqual(ReferenceBox(reference)))
  }
}
