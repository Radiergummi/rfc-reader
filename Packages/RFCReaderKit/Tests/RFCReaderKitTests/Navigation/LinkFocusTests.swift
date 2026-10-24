import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Tab and Shift-Tab through the reader's links (#711): which link the focus moves to,
/// a pure function of the built text, the focused link and what is on screen.
@Suite("Link focus")
struct LinkFocusTests {
  private static func rfc8999() throws -> BuiltDocument {
    DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle())
  }

  /// Whether `range` is a whole link: carried by every character of it, and by
  /// neither character beside it, where that carries another link or none.
  private static func isWholeLink(_ range: NSRange, in text: NSAttributedString) -> Bool {
    guard range.length > 0,
      let link = text.attribute(.link, at: range.location, effectiveRange: nil)
    else { return false }
    var extent = NSRange()
    _ = text.attribute(
      .link, at: range.location, longestEffectiveRange: &extent,
      in: NSRange(location: 0, length: text.length))
    return extent == range
      && (link as AnyObject).isEqual(
        text.attribute(.link, at: NSMaxRange(range) - 1, effectiveRange: nil))
  }

  /// Whether no character of `range` is part of a link.
  private static func hasNoLink(in range: NSRange, of text: NSAttributedString) -> Bool {
    var found = false
    text.enumerateAttribute(.link, in: range) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return !found
  }

  @Test func `tab from nothing focuses the first link on screen`() throws {
    let text = try Self.rfc8999().text
    let screen = NSRange(location: text.length / 3, length: 2_000)
    let link = try #require(
      LinkFocus.link(.next, from: nil, on: screen, in: text, hidden: HiddenText()))
    #expect(Self.isWholeLink(link, in: text))
    #expect(NSMaxRange(link) > screen.location)
    if link.location > screen.location {
      #expect(
        Self.hasNoLink(
          in: NSRange(location: screen.location, length: link.location - screen.location),
          of: text))
    }
  }

  @Test func `shift-tab from nothing focuses the last link on screen`() throws {
    let text = try Self.rfc8999().text
    let screen = NSRange(location: text.length / 3, length: 2_000)
    let link = try #require(
      LinkFocus.link(.previous, from: nil, on: screen, in: text, hidden: HiddenText()))
    #expect(Self.isWholeLink(link, in: text))
    #expect(link.location < NSMaxRange(screen))
    if NSMaxRange(link) < NSMaxRange(screen) {
      #expect(
        Self.hasNoLink(
          in: NSRange(location: NSMaxRange(link), length: NSMaxRange(screen) - NSMaxRange(link)),
          of: text))
    }
  }

  @Test func `tab and shift-tab step from link to link and back`() throws {
    let text = try Self.rfc8999().text
    let screen = NSRange(location: 0, length: 0)
    let first = try #require(
      LinkFocus.link(.next, from: nil, on: screen, in: text, hidden: HiddenText()))
    let second = try #require(
      LinkFocus.link(.next, from: first, on: screen, in: text, hidden: HiddenText()))
    #expect(Self.isWholeLink(second, in: text))
    #expect(second.location >= NSMaxRange(first))
    #expect(
      Self.hasNoLink(
        in: NSRange(location: NSMaxRange(first), length: second.location - NSMaxRange(first)),
        of: text))
    #expect(
      LinkFocus.link(.previous, from: second, on: screen, in: text, hidden: HiddenText()) == first)
    #expect(
      LinkFocus.link(.previous, from: first, on: screen, in: text, hidden: HiddenText()) == nil)
  }

  /// Past the last link Tab goes nowhere, and the text view moves the focus on.
  @Test func `past the last link there is none`() throws {
    let text = try Self.rfc8999().text
    let end = NSRange(location: text.length, length: 0)
    let last = try #require(
      LinkFocus.link(.previous, from: nil, on: end, in: text, hidden: HiddenText()))
    #expect(LinkFocus.link(.next, from: last, on: end, in: text, hidden: HiddenText()) == nil)
  }

  /// A link in a section a reading mode folds is not on the page to focus.
  @Test func `a folded link is passed over`() throws {
    let built = try Self.rfc8999()
    let outline = Folding(mode: .outline).hidden(in: built.foldingIndex)
    let shown = Self.links(in: built.text, hidden: outline)
    #expect(shown.allSatisfy { !outline.contains($0.location) })
    #expect(shown.count < Self.links(in: built.text, hidden: HiddenText()).count)
  }

  /// A heading's hung number (#433) links to its own heading: going there from the
  /// heading is no stop to make.
  @Test func `a heading's hung number is passed over`() throws {
    var style = ReadingStyle()
    style.sectionNumberHang = 30
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
    let text = built.text
    var numbers = 0
    text.enumerateAttribute(.rfcSectionNumber, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      if value != nil { numbers += 1 }
    }
    #expect(numbers > 0)
    for link in Self.links(in: text, hidden: HiddenText()) {
      #expect(text.attribute(.rfcSectionNumber, at: link.location, effectiveRange: nil) == nil)
    }
  }

  /// Every link Tab stops at from the top of the text, in order.
  private static func links(in text: NSAttributedString, hidden: HiddenText) -> [NSRange] {
    let top = NSRange(location: 0, length: 0)
    var links: [NSRange] = []
    while let next = LinkFocus.link(.next, from: links.last, on: top, in: text, hidden: hidden) {
      links.append(next)
    }
    return links
  }
}
