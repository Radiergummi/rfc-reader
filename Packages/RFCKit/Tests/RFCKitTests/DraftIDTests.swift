import Foundation
import Testing

@testable import RFCKit

@Suite("DraftID")
struct DraftIDTests {
  @Test(
    arguments: [
      ("draft-ietf-httpbis-semantics-19", "draft-ietf-httpbis-semantics", "19"),
      ("draft-ietf-httpbis-semantics", "draft-ietf-httpbis-semantics", nil),
      ("  Draft-IETF-HTTPbis-Semantics-00 ", "draft-ietf-httpbis-semantics", "00"),
      ("draft-ietf-httpbis-rfc6265bis-22", "draft-ietf-httpbis-rfc6265bis", "22"),
      ("draft-ietf-quic-http-34", "draft-ietf-quic-http", "34"),
      ("draft-west-cookies", "draft-west-cookies", nil),
      // A three-digit last part is a part of the name, never a revision.
      ("draft-ietf-sidr-rfc6485bis-100", "draft-ietf-sidr-rfc6485bis-100", nil),
    ] as [(String, String, String?)])
  func `parses a draft's name, with its revision or without`(
    input: String, name: String, revision: String?
  ) throws {
    let id = try #require(DraftID(parsing: input))
    #expect(id.name == name)
    #expect(id.revision == revision)
  }

  @Test(
    arguments: [
      "", "draft", "draft-", "draft-foo", "draft-foo-07", "rfc9110", "9110", "draft--foo-bar",
      "draft-foo-bar-", "draft-foo bar", "draft-foo_bar", "draft-19", "draft-fóo-bar",
    ])
  func `rejects what is not a draft's name`(input: String) {
    #expect(DraftID(parsing: input) == nil)
  }

  @Test func `a revision is two digits`() {
    #expect(DraftID(name: "draft-foo-bar", revision: "1") == nil)
    #expect(DraftID(name: "draft-foo-bar", revision: "100") == nil)
    #expect(DraftID(name: "draft-foo-bar", revision: "ab") == nil)
    #expect(DraftID(name: "draft-foo-bar", revision: "07")?.description == "draft-foo-bar-07")
  }

  @Test func `the app's URL names the draft, and the newest without a revision`() throws {
    let revision = try #require(DraftID(parsing: "draft-ietf-httpbis-semantics-19"))
    #expect(revision.appURL.absoluteString == "rfc://draft-ietf-httpbis-semantics-19")
    let newest = try #require(revision.at(revision: nil))
    #expect(newest.appURL.absoluteString == "rfc://draft-ietf-httpbis-semantics")
    #expect(DraftLink(url: revision.appURL)?.id == revision)
    #expect(DraftLink(url: newest.appURL)?.id == newest)
  }

  /// A draft's name never parses as an RFC, so `rfc://draft-…` and `rfc://9110`
  /// cannot be read as each other.
  @Test func `a draft's name is never a document of a series`() throws {
    let url = try #require(URL(string: "rfc://draft-ietf-httpbis-rfc6265bis-22"))
    #expect(RFCLink(url: url) == nil)
    #expect(DocumentID(parsing: "draft-ietf-httpbis-rfc6265bis-22") == nil)
    #expect(ReadableLink(url: url)?.document == .draft(DraftID(parsing: url.host()!)!))
    let rfc = try #require(URL(string: "rfc://9110"))
    #expect(DraftLink(url: rfc) == nil)
    #expect(ReadableLink(url: rfc)?.document == .rfc(.rfc(9110)))
  }

  @Test func `a readable document names itself as the RFC or draft it is`() throws {
    let draft = try #require(DraftID(parsing: "draft-ietf-quic-http-34"))
    #expect(ReadableDocument.rfc(.rfc(9110)).displayName == "RFC 9110")
    #expect(ReadableDocument.draft(draft).displayName == "draft-ietf-quic-http-34")
    #expect(ReadableDocument.draft(draft).draft == draft)
    #expect(ReadableDocument.draft(draft).rfc == nil)
    let encoded = try JSONEncoder().encode(ReadableDocument.draft(draft))
    #expect(try JSONDecoder().decode(ReadableDocument.self, from: encoded) == .draft(draft))
  }
}

@Suite("Draft links")
struct DraftLinkTests {
  private static func draft(_ text: String) -> DraftID { DraftID(parsing: text)! }

  @Test(
    arguments: [
      ("rfc://draft-ietf-quic-http-34", DraftLink(id: draft("draft-ietf-quic-http-34"))),
      (
        "rfc://draft-ietf-quic-http#section-4.2",
        DraftLink(id: draft("draft-ietf-quic-http"), section: "4.2")
      ),
      (
        "https://datatracker.ietf.org/doc/draft-ietf-quic-http/",
        DraftLink(id: draft("draft-ietf-quic-http"))
      ),
      (
        "https://datatracker.ietf.org/doc/draft-ietf-quic-http/34/",
        DraftLink(id: draft("draft-ietf-quic-http-34"))
      ),
      (
        "https://datatracker.ietf.org/doc/html/draft-ietf-quic-http-34#section-7.2.4",
        DraftLink(id: draft("draft-ietf-quic-http-34"), section: "7.2.4")
      ),
      (
        "https://datatracker.ietf.org/doc/html/draft-ietf-quic-http",
        DraftLink(id: draft("draft-ietf-quic-http"))
      ),
      (
        "https://datatracker.ietf.org/doc/draft-ietf-quic-http-34/",
        DraftLink(id: draft("draft-ietf-quic-http-34"))
      ),
      (
        "https://tools.ietf.org/html/draft-ietf-quic-http-34",
        DraftLink(id: draft("draft-ietf-quic-http-34"))
      ),
      (
        "https://www.ietf.org/archive/id/draft-ietf-quic-http-34.txt",
        DraftLink(id: draft("draft-ietf-quic-http-34"))
      ),
      (
        "https://www.ietf.org/archive/id/draft-ietf-quic-http-34.xml#name-overview",
        DraftLink(id: draft("draft-ietf-quic-http-34"), anchor: "name-overview")
      ),
      (
        "https://www.ietf.org/id/draft-ietf-quic-http-34.txt",
        DraftLink(id: draft("draft-ietf-quic-http-34"))
      ),
    ])
  func `recognizes the ways drafts get linked`(input: String, expected: DraftLink) throws {
    let url = try #require(URL(string: input))
    #expect(DraftLink(url: url) == expected)
    #expect(ReadableLink(url: url) == .draft(expected))
  }

  @Test(
    arguments: [
      "https://datatracker.ietf.org/doc/draft-ietf-quic-http/history/",
      "https://datatracker.ietf.org/doc/draft-ietf-quic-http/ballot/",
      "https://datatracker.ietf.org/doc/draft-ietf-quic-http-34/34/",
      "https://datatracker.ietf.org/doc/rfc9114/",
      "https://datatracker.ietf.org/wg/quic/about/",
      "https://www.ietf.org/archive/id/draft-ietf-quic-http-34.json",
      "https://www.ietf.org/about/draft-ietf-quic-http-34.txt",
      "https://example.com/doc/draft-ietf-quic-http-34",
    ])
  func `ignores pages about a draft and other addresses`(input: String) throws {
    let url = try #require(URL(string: input))
    #expect(DraftLink(url: url) == nil)
  }

  @Test func `a link goes back to the app's URL it came from`() throws {
    let link = DraftLink(id: Self.draft("draft-ietf-quic-http-34"), section: "4.2 x#1")
    #expect(link.appURL.absoluteString == "rfc://draft-ietf-quic-http-34#section-4.2%20x%231")
    #expect(DraftLink(url: link.appURL) == link)
    #expect(ReadableLink.draft(link).appURL == link.appURL)
    #expect(ReadableLink.draft(link).place == "4.2 x#1")
  }
}
