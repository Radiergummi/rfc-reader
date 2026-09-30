import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Selection text")
struct SelectionTextTests {
  private func copied(_ inlines: [Inline]) -> String {
    SelectionText.plainText(of: Fixtures.inlineRun(inlines))
  }

  @Test func `ordinary prose is copied as it is`() {
    #expect(copied([.text("hello world")]) == "hello world")
  }

  /// The whole reason this exists: the chip's symbol rides in the text as an
  /// object-replacement character, which means nothing off the screen.
  @Test func `no object replacement character reaches the pasteboard`() {
    let text = copied([
      .text("see "), .crossReference(CrossReference(target: .document(.rfc(9110), section: nil))),
    ])
    #expect(
      !text.contains("\u{FFFC}"), "U+FFFC is the chip's symbol, not text: \(text.debugDescription)")
    #expect(!text.contains("\u{2060}"), "nor the word joiner behind it")
  }

  @Test func `a reference is copied with its brackets`() {
    #expect(
      copied([.crossReference(CrossReference(target: .document(.rfc(9110), section: nil)))])
        == "[RFC 9110]")
  }

  /// The brackets earn their place here: on screen the chip's tint separates two
  /// adjacent references, and a pasteboard has no tint.
  @Test func `adjacent references do not run together`() {
    let text = copied([
      .text("see "),
      .crossReference(CrossReference(target: .document(.rfc(9110), section: nil))),
      .text(" "),
      .crossReference(CrossReference(target: .document(.rfc(9111), section: nil))),
    ])
    #expect(text == "see [RFC 9110] [RFC 9111]")
  }

  @Test func `a section reference is copied as the phrase it reads`() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    #expect(copied([.crossReference(xref)]) == "Section 4.2 of [RFC 9110]")
  }

  /// Non-breaking spaces stop a chip wrapping mid-label in a narrow column. That is
  /// a fact about a text view, and has no business in a mail or a terminal.
  @Test func `typesetting does not travel to the pasteboard`() {
    let text = copied([
      .crossReference(CrossReference(target: .document(.rfc(9110), section: "4.2")))
    ])
    #expect(
      !text.contains("\u{00A0}"), "a non-breaking space is typesetting: \(text.debugDescription)")
  }

  @Test func `an authors own words are copied as written`() {
    let xref = CrossReference(
      target: .document(.rfc(9110), section: "4.2"), text: "the caching rules")
    #expect(copied([.text("see "), .crossReference(xref)]) == "see the caching rules")
  }

  @Test func `a documents own tag is copied as written`() {
    let xref = CrossReference(target: .document(.rfc(9000), section: nil), text: "[QUIC-TRANSPORT]")
    #expect(copied([.crossReference(xref)]) == "[QUIC-TRANSPORT]")
  }

  @Test func `an anchor reference keeps its own text`() {
    let xref = CrossReference(target: .anchor("section-3"), text: "Section 3")
    #expect(copied([.text("in "), .crossReference(xref)]) == "in Section 3")
  }

  /// A chip is one thing on screen; there is no half of it that means anything. A
  /// selection that starts inside one still yields a whole label rather than the
  /// tail of one — which is also what stops a selection beginning after the symbol
  /// from copying a bare fragment.
  @Test func `a partly selected reference still copies whole`() {
    let whole = Fixtures.inlineRun([
      .crossReference(CrossReference(target: .document(.rfc(9110), section: nil)))
    ])
    let tail = whole.attributedSubstring(from: NSRange(location: whole.length - 2, length: 2))
    #expect(SelectionText.plainText(of: tail) == "[RFC 9110]")
  }

  @Test func `an empty selection copies nothing`() {
    #expect(SelectionText.plainText(of: NSAttributedString(string: "")) == "")
  }
}
