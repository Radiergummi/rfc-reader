import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Toolbar subtitle")
struct ToolbarSubtitleTests {
  /// Two sections, their headings at offsets 100 and 500. Everything before 100 is
  /// the title page and the abstract.
  private let sections = AnchorIndex([
    AnchorIndex.Entry(anchor: "section-1", offset: 100, heading: "1. Introduction"),
    AnchorIndex.Entry(anchor: "section-2", offset: 500, heading: "2. Terminology"),
  ])

  private func state(at start: Int, crossing: CGFloat = 0) -> ToolbarSubtitle.State {
    ToolbarSubtitle.state(in: sections, topFragmentStart: start, crossing: crossing)
  }

  /// The abstract belongs to no section, so the document's title stays.
  @Test func theDocumentsTitleUntilTheFirstHeading() {
    #expect(state(at: 0) == .steady(nil))
    #expect(
      state(at: 60, crossing: 0.5) == .steady(nil),
      "a crossing paragraph that is not a heading changes nothing")
  }

  /// The first heading hands over from the document's title, scrubbing with it.
  @Test func theFirstHeadingReplacesTheDocumentsTitle() {
    let crossing = state(at: 100, crossing: 0.25)
    #expect(
      crossing == ToolbarSubtitle.State(outgoing: nil, incoming: "1. Introduction", progress: 0.25))
  }

  /// Inside a section, its heading shows outright.
  @Test func aSectionsHeadingHoldsThroughItsBody() {
    #expect(state(at: 250, crossing: 0.7) == .steady("1. Introduction"))
  }

  /// Each heading hands over from the one before it.
  @Test func aLaterHeadingReplacesTheOneBefore() {
    let crossing = state(at: 500, crossing: 0.5)
    #expect(
      crossing
        == ToolbarSubtitle.State(
          outgoing: "1. Introduction", incoming: "2. Terminology", progress: 0.5))
  }

  /// A heading still wholly below the edge is all outgoing; one wholly past it is
  /// all incoming — the two ends of the same hand-over, which is what makes
  /// scrolling back up play it in reverse.
  @Test func theHandOverRunsBothWays() {
    #expect(state(at: 500, crossing: 0).progress == 0)
    #expect(state(at: 500, crossing: 1).progress == 1)
  }

  /// A document with no sections keeps its title throughout.
  @Test func noSectionsKeepsTheDocumentsTitle() {
    let none = ToolbarSubtitle.state(in: AnchorIndex([]), topFragmentStart: 900, crossing: 1)
    #expect(none == .steady(nil))
  }
}
