import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Annotations: a note's links")
struct NoteLinkTests {
  @Test(arguments: [
    ("RFC 9110", "rfc://9110"),
    ("9110", "rfc://9110"),
    ("RFC 9110 Section 4.2", "rfc://9110#section-4.2"),
    ("RFC 9110, Section 4.2", "rfc://9110#section-4.2"),
    ("rfc9110 §4.2", "rfc://9110#section-4.2"),
    ("9110#section-4.2", "rfc://9110#section-4.2"),
    ("BCP 14", "rfc://bcp14"),
    ("https://www.rfc-editor.org/rfc/rfc9110#section-4.2", "rfc://9110#section-4.2"),
    ("rfc://9110#section-4.2", "rfc://9110#section-4.2"),
  ])
  func `what names an RFC is the app's own link`(typed: String, url: String) {
    #expect(NoteLink.url(from: typed)?.absoluteString == url)
  }

  @Test func `a web address is itself, with https assumed`() {
    #expect(NoteLink.url(from: "https://example.org/a")?.absoluteString == "https://example.org/a")
    #expect(NoteLink.url(from: "example.org/page")?.absoluteString == "https://example.org/page")
    #expect(NoteLink.url(from: "mailto:a@example.org")?.absoluteString == "mailto:a@example.org")
  }

  @Test func `anything else is no link`() {
    #expect(NoteLink.url(from: "") == nil)
    #expect(NoteLink.url(from: "just some words") == nil)
    #expect(NoteLink.url(from: "javascript:alert(1)") == nil)
  }

  @Test func `a pasted address of an RFC becomes the app's link, and other text does not`() {
    #expect(
      NoteLink.pasted("https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2")?.absoluteString
        == "rfc://9110#section-4.2")
    #expect(NoteLink.pasted("rfc://9110")?.absoluteString == "rfc://9110")
    #expect(NoteLink.pasted("https://example.org") == nil)
    #expect(NoteLink.pasted("RFC 9110 says") == nil)
  }
}
