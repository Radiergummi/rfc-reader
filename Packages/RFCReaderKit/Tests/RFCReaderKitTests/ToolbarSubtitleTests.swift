import CoreGraphics
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

@Suite("Toolbar subtitle crossing")
struct ToolbarSubtitleCrossingTests {
  /// A heading fragment at y = 100 with 12 pt of space above its one 30 pt line,
  /// which therefore runs from 112 to 142.
  private func crossing(atEdge edge: CGFloat) -> CGFloat {
    ToolbarSubtitle.crossing(
      edge: edge, fragmentTop: 100, fragmentHeight: 42,
      lastLine: CGRect(x: 0, y: 12, width: 300, height: 30))
  }

  /// The space above a heading is not the heading: nothing moves until the line
  /// itself reaches the edge.
  @Test func theSpaceAboveTheLineIsNotCounted() {
    #expect(crossing(atEdge: 100) == 0)
    #expect(crossing(atEdge: 112) == 0)
  }

  @Test func followsTheLineAcrossTheEdge() {
    #expect(crossing(atEdge: 127) == 0.5)
    #expect(crossing(atEdge: 142) == 1)
  }

  /// A wrapped heading hands over on its last line: with that line at 142–172,
  /// the edge halfway down the first line has not started it.
  @Test func aWrappedHeadingHandsOverOnItsLastLine() {
    let wrapped: (CGFloat) -> CGFloat = { edge in
      ToolbarSubtitle.crossing(
        edge: edge, fragmentTop: 100, fragmentHeight: 72,
        lastLine: CGRect(x: 0, y: 42, width: 300, height: 30))
    }
    #expect(wrapped(127) == 0)
    #expect(wrapped(157) == 0.5)
  }

  /// A fragment without lines counts as one line its own height.
  @Test func aFragmentWithoutLinesIsOneLine() {
    let bare = ToolbarSubtitle.crossing(
      edge: 120, fragmentTop: 100, fragmentHeight: 40, lastLine: nil)
    #expect(bare == 0.5)
  }
}
