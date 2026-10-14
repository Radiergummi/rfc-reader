import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Whether a link or an attachment is beside a caret position: what the reader's
/// text view asks before it lets AppKit's accessibility hit test walk every link in
/// the document (#396). A point between two characters may be on either, so both
/// count.
struct AccessibilityChildNearTests {
  /// `see ` + a link over `RFC 9110` + ` here`.
  private let text: NSAttributedString = {
    let text = NSMutableAttributedString(string: "see ")
    text.append(
      NSAttributedString(
        string: "RFC 9110", attributes: [.link: URL(string: "rfc://9110") as Any]))
    text.append(NSAttributedString(string: " here"))
    return text
  }()

  @Test func `a caret inside or at either edge of a link is beside it`() {
    #expect(text.hasAccessibilityChild(besideInsertionIndex: 4), "before its first character")
    #expect(text.hasAccessibilityChild(besideInsertionIndex: 8), "inside it")
    #expect(text.hasAccessibilityChild(besideInsertionIndex: 12), "after its last character")
  }

  @Test func `a caret in plain text away from a link is not`() {
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: 1))
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: 14))
  }

  @Test func `an attachment is beside a caret too`() {
    let text = NSMutableAttributedString(string: "a ")
    text.append(NSAttributedString(attachment: NSTextAttachment()))
    text.append(NSAttributedString(string: " b"))
    #expect(text.hasAccessibilityChild(besideInsertionIndex: 2))
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: 0))
  }

  @Test func `the ends of the text are asked safely`() {
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: 0))
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: text.length))
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: -1))
    #expect(!text.hasAccessibilityChild(besideInsertionIndex: text.length + 5))
  }
}
