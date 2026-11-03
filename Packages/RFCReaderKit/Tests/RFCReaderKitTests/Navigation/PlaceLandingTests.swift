import RFCKit
import Testing

@testable import RFCReaderKit

/// Where a place handed to the reader lands, given whether the RFC is read as its
/// original (#1031): the hidden pointer text's places are not shown.
@Suite("Place landing")
struct PlaceLandingTests {
  private let document = RFCDocument(
    header: DocumentHeader(title: "T"),
    sections: [
      RFCKit.Section(anchor: "section-1", number: "1", title: "Introduction"),
      RFCKit.Section(anchor: "sample-varint", number: "A.1", title: "Sample", isAppendix: true),
    ],
    source: .xml)
  private let bibliography = [
    ReferenceGroup(
      title: "Normative References", entries: [Reference(anchor: "RFC3986", title: "URI")])
  ]
  /// What the build holds: the two sections, and a paragraph's anchor no section names.
  private let anchors = AnchorIndex([
    AnchorIndex.Entry(anchor: "section-1", offset: 0, heading: "1. Introduction"),
    AnchorIndex.Entry(anchor: "section-1-2", offset: 40),
    AnchorIndex.Entry(anchor: "sample-varint", offset: 80, heading: "A.1. Sample"),
  ])

  private func landing(
    at place: String, readAsOriginal kind: PublishedOriginalPage.Kind?, built: Bool = true
  ) -> PlaceLanding? {
    PlaceLanding.landing(
      at: place, in: built ? DocumentPlaces(document: document, anchors: anchors) : nil,
      bibliography: bibliography, readAsOriginal: kind)
  }

  /// An RFC read as its original shows no text whose places a deep link, Back or
  /// Forward could go to (#1031): a pointer's loaded text holds them, but is not the
  /// RFC, and its page does not show it. That needs no build to say, so a script's
  /// jump does not wait for one that page never shows.
  @Test(arguments: ["1", "section-1-2", "RFC3986", "page-12"])
  func `a place in an RFC read as its original is not shown`(place: String) {
    #expect(landing(at: place, readAsOriginal: .pointer) == .notShown)
    #expect(landing(at: place, readAsOriginal: .pointer, built: false) == .notShown)
    #expect(landing(at: place, readAsOriginal: .scan, built: false) == .notShown)
  }

  /// An RFC read as its text lands where the build puts the place, in either mode,
  /// and waits for its build to say.
  @Test func `a place in an RFC read as its text lands in it`() {
    #expect(landing(at: "1", readAsOriginal: nil) == .inText(.jump("section-1")))
    #expect(landing(at: "RFC3986", readAsOriginal: nil) == .inText(.reference("RFC3986")))
    #expect(landing(at: "page-12", readAsOriginal: nil) == .inText(.unhandled))
    #expect(landing(at: "1", readAsOriginal: nil, built: false) == nil)
  }
}
