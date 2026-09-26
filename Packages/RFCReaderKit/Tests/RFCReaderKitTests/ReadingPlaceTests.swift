import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Reading place")
struct ReadingPlaceTests {
  private let index = AnchorIndex([
    .init(anchor: "section-1", offset: 100, heading: "1. Section"),
    .init(anchor: "section-1-1", offset: 130),
    .init(anchor: "section-2", offset: 400, heading: "2. Section"),
  ])

  @Test func recordsTheNearestAnchorOfAnyKindAndTheDistanceIntoIt() {
    // A paragraph anchor, not the section: restoring to the section would put
    // the reader back at its heading, a screenful or more from where they were.
    #expect(ReadingPlace(at: 250, in: index) == ReadingPlace(anchor: "section-1-1", offset: 120))
    #expect(ReadingPlace(at: 400, in: index) == ReadingPlace(anchor: "section-2", offset: 0))
  }

  @Test func roundTripsThroughTheSameIndex() {
    for offset in [0, 99, 100, 129, 130, 250, 399, 400, 480] {
      let place = ReadingPlace(at: offset, in: index)
      #expect(place.documentOffset(in: index, length: 500) == offset)
    }
  }

  @Test func aPlaceAheadOfTheFirstAnchorIsTheDistanceFromTheDocumentStart() {
    #expect(ReadingPlace(at: 40, in: index) == ReadingPlace(anchor: nil, offset: 40))
  }

  @Test func followsItsAnchorToWhereverTheRebuildPutIt() {
    let rebuilt = AnchorIndex([
      .init(anchor: "section-1", offset: 100, heading: "1. Section"),
      .init(anchor: "section-1-1", offset: 180),
      .init(anchor: "section-2", offset: 460, heading: "2. Section"),
    ])
    #expect(
      ReadingPlace(anchor: "section-1-1", offset: 120).documentOffset(in: rebuilt, length: 600)
        == 300)
  }

  @Test func staysInsideItsBlockWhenTheBlockCameBackShorter() {
    // A table re-shaped for a narrower column can hold fewer characters; the
    // place must not spill into whatever follows it.
    let rebuilt = AnchorIndex([
      .init(anchor: "section-1-1", offset: 130),
      .init(anchor: "section-2", offset: 200, heading: "2. Section"),
    ])
    #expect(
      ReadingPlace(anchor: "section-1-1", offset: 120).documentOffset(in: rebuilt, length: 600)
        == 199)
    #expect(
      ReadingPlace(anchor: "section-2", offset: 900).documentOffset(in: rebuilt, length: 600) == 599
    )
  }

  @Test func anAnchorTheRebuildNoLongerHasResolvesToNothing() {
    #expect(ReadingPlace(anchor: "gone", offset: 3).documentOffset(in: index, length: 500) == nil)
  }

  @Test func keepsThePlaceWhileItsLineIsStillAtTheTop() {
    let previous = ReadingPlace(anchor: "section-1-1", offset: 120)
    // The line holding offset 250 after a restore at another column, starting
    // earlier than the place does.
    let line = NSRange(location: 230, length: 60)
    #expect(ReadingPlace.tracking(previous, topLine: line, in: index, length: 500) == previous)
  }

  @Test func movesToTheLinesStartOnceTheReaderReachesAnotherLine() {
    let previous = ReadingPlace(anchor: "section-1-1", offset: 120)
    let next = NSRange(location: 290, length: 60)
    #expect(
      ReadingPlace.tracking(previous, topLine: next, in: index, length: 500)
        == ReadingPlace(anchor: "section-1-1", offset: 160))
    #expect(
      ReadingPlace.tracking(nil, topLine: next, in: index, length: 500)
        == ReadingPlace(anchor: "section-1-1", offset: 160))
  }

  /// Resizing back and forth — a live resize, rebuilding each time it pauses —
  /// comes back to the line it started on, however the two columns wrap.
  @Test func doesNotWalkBackAcrossRebuildsAtAlternatingColumns() {
    var place = ReadingPlace(anchor: "section-1-1", offset: 120)
    // At the narrow column the line holding 250 starts at 232; at the wide one,
    // at 241 — both earlier than the place itself.
    for line in [
      NSRange(location: 232, length: 50), NSRange(location: 241, length: 70),
      NSRange(location: 232, length: 50),
    ] {
      place = ReadingPlace.tracking(place, topLine: line, in: index, length: 500)
    }
    #expect(place == ReadingPlace(anchor: "section-1-1", offset: 120))
  }

  /// The property the reader relies on: the same text is at the top before and
  /// after a resize rebuilds the document at another measure. A table ahead of
  /// the needle grids at the wide measure and stacks at the narrow one, so the
  /// storage genuinely changes length and a carried raw offset would miss.
  @Test func findsTheSameTextInADocumentBuiltAtAnotherMeasure() throws {
    let table = RFCKit.Table(
      title: "Status Codes",
      number: 1,
      header: [[[.text("Code")], [.text("Description")], [.text("Ref.")]]],
      rows: [
        [[.text("404")], [.text("Not found, which is a short description")], [.text("6.5.4")]]
      ],
      anchor: "table-1"
    )
    let needle = "The needle paragraph follows the table."
    let document = Fixtures.document(
      .table(table), .paragraph(Paragraph(text: needle, anchor: "section-1-2")))
    let wide = DocumentTextBuilder.build(document, style: ReadingStyle(measure: 712))
    let narrow = DocumentTextBuilder.build(document, style: ReadingStyle(measure: 200))
    try #require(
      wide.text.length != narrow.text.length, "the two measures must shape the table differently")

    let original = try Fixtures.offset(of: needle, in: wide.text) + 7
    let place = ReadingPlace(at: original, in: wide.anchors)
    let restored = try #require(
      place.documentOffset(in: narrow.anchors, length: narrow.text.length))
    let expected = (wide.text.string as NSString).substring(
      with: NSRange(location: original, length: 20))
    #expect(
      (narrow.text.string as NSString).substring(with: NSRange(location: restored, length: 20))
        == expected)
  }
}

@Suite("Reading place: line geometry")
@MainActor
struct ReadingPlaceLineGeometryTests {
  private struct Laid {
    let lines: [NSTextLineFragment]
    let fragment: NSRange
    let frameTop: CGFloat
    let frameHeight: CGFloat
    var fragmentStart: Int { fragment.location }
  }

  /// One paragraph wrapped over many lines, laid out by TextKit 2, starting past
  /// the document's first character so a fragment-relative slip shows.
  private func paragraph(spacing: CGFloat = 0) throws -> Laid {
    let font = PlatformFont.systemFont(ofSize: 17)
    let prose = (0..<80).map { "word\($0)" }.joined(separator: " ")
    let style = NSMutableParagraphStyle()
    style.paragraphSpacing = spacing
    let storage = NSTextContentStorage()
    storage.attributedString = NSAttributedString(
      string: "Heading\n" + prose + "\nAfter",
      attributes: [.font: font, .paragraphStyle: style]
    )
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 300, height: 100_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    var found: Laid?
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      let start = layout.offset(of: fragment.rangeInElement.location)
      let end = layout.offset(of: fragment.rangeInElement.endLocation)
      if start > 0 {
        found = Laid(
          lines: fragment.textLineFragments,
          fragment: NSRange(location: start, length: end - start),
          frameTop: fragment.layoutFragmentFrame.minY,
          frameHeight: fragment.layoutFragmentFrame.height
        )
      }
      return found == nil
    }
    let paragraph = try #require(found)
    try #require(paragraph.lines.count > 3, "the fixture must wrap")
    return paragraph
  }

  @Test func aPointInsideALineNamesThatLinesCharacters() throws {
    let paragraph = try paragraph()
    for line in paragraph.lines {
      let range = FragmentGeometry.lineRange(
        at: line.typographicBounds.midY, in: paragraph.lines, fragment: paragraph.fragment)
      #expect(
        range
          == NSRange(
            location: paragraph.fragmentStart + line.characterRange.location,
            length: line.characterRange.length))
    }
  }

  @Test func aPointAboveTheFirstLineNamesTheFirstLine() throws {
    let paragraph = try paragraph()
    #expect(
      FragmentGeometry.lineRange(at: -5, in: paragraph.lines, fragment: paragraph.fragment).location
        == paragraph.fragmentStart)
  }

  @Test func anOffsetAnywhereInALineFindsThatLinesTop() throws {
    let paragraph = try paragraph()
    for line in paragraph.lines {
      let middle =
        paragraph.fragmentStart + line.characterRange.location + line.characterRange.length / 2
      #expect(
        FragmentGeometry.lineTop(
          of: middle, in: paragraph.lines, fragmentStart: paragraph.fragmentStart)
          == line.typographicBounds.minY)
    }
  }

  @Test func theTwoAreInverses() throws {
    let paragraph = try paragraph()
    for line in paragraph.lines {
      let range = FragmentGeometry.lineRange(
        at: line.typographicBounds.minY, in: paragraph.lines, fragment: paragraph.fragment)
      #expect(
        FragmentGeometry.lineTop(
          of: range.location, in: paragraph.lines, fragmentStart: paragraph.fragmentStart)
          == line.typographicBounds.minY)
    }
  }

  /// A fragment's frame runs on past its last line by the paragraph spacing, and
  /// a viewport top in that gap has already scrolled past every line of it. The
  /// line it is reading is the next paragraph's first; naming this paragraph's
  /// start would send the next rebuild back up by the paragraph's whole height.
  @Test func aPointInTheSpacingBelowTheLastLineNamesTheNextParagraph() throws {
    let paragraph = try paragraph(spacing: 20)
    let lastLine = try #require(paragraph.lines.last).typographicBounds.maxY
    try #require(
      paragraph.frameHeight > lastLine + 10, "the frame must carry the spacing below its last line")
    let range = FragmentGeometry.lineRange(
      at: lastLine + 10, in: paragraph.lines, fragment: paragraph.fragment)
    #expect(range == NSRange(location: NSMaxRange(paragraph.fragment), length: 0))
  }

  /// What the coordinator does with the two: scroll so the line holding an
  /// offset is at the top, then read the top of the viewport back. The first
  /// line is scrolled to the fragment's top, spacing above it included, and
  /// every other line to its own top; the read-back must name that line either
  /// way, including when the scroll view has rounded the offset down to a pixel.
  @Test func aLineScrolledToTheTopIsReadBackAsThatLine() throws {
    let paragraph = try paragraph(spacing: 20)
    for line in paragraph.lines {
      let start = paragraph.fragmentStart + line.characterRange.location
      for offset in [start, start + line.characterRange.length / 2] {
        let target =
          paragraph.frameTop
          + FragmentGeometry.scrollTarget(
            of: offset, in: paragraph.lines, fragmentStart: paragraph.fragmentStart)
        for top in [target, (target * 2).rounded(.down) / 2 - 0.5] {
          let read = FragmentGeometry.topLine(
            atViewportTop: top,
            fragmentTop: paragraph.frameTop,
            in: paragraph.lines,
            fragmentStart: paragraph.fragmentStart,
            fragmentEnd: NSMaxRange(paragraph.fragment)
          )
          #expect(read == NSRange(location: start, length: line.characterRange.length))
        }
      }
    }
  }

  @Test func theFragmentsFirstCharacterScrollsToTheFragmentsTop() throws {
    let paragraph = try paragraph(spacing: 20)
    #expect(
      FragmentGeometry.scrollTarget(
        of: paragraph.fragmentStart, in: paragraph.lines, fragmentStart: paragraph.fragmentStart)
        == 0)
  }
}

@Suite("Reading place tracker")
struct ReadingPlaceTrackerTests {
  private let index = AnchorIndex([
    .init(anchor: "section-1", offset: 100, heading: "1. Section"),
    .init(anchor: "section-1-1", offset: 130),
    .init(anchor: "section-2", offset: 400, heading: "2. Section"),
  ])
  private let wide: CGFloat = 712
  private let narrow: CGFloat = 480

  /// Laid out at `wide`, tracking, and reading the line starting at 250.
  private func reading() -> ReadingPlaceTracker {
    var tracker = ReadingPlaceTracker()
    let laysOutWide = tracker.columnChanged(to: wide)
    #expect(!laysOutWide, "nothing is installed yet")
    tracker.installed(atColumn: wide)
    tracker.restored(top: nil)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 250, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    return tracker
  }

  @Test func tracksTheLineAtTheTop() {
    var tracker = reading()
    tracker.report(
      viewportTop: 340, line: NSRange(location: 310, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 180)))
  }

  @Test func aChangeOfColumnPausesTrackingUntilTheStorageIsLaidOutAgain() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    // The old storage, re-wrapped under an unmoved offset: text the reader never saw.
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    tracker.installed(atColumn: narrow)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(
      tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)),
      "installed is not yet restored")
    tracker.restored(top: nil)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: nil, offset: 20)))
  }

  /// Wide, narrow and wide again inside the rebuild's debounce. The container is
  /// back at the width the storage was laid out at, but TextKit threw that layout
  /// away at the narrow one, and what it shows now is estimated: keyed on the
  /// width alone, tracking resumed here and recorded a line the reader never saw.
  @Test func aColumnThatComesBackDoesNotResumeTrackingOnDiscardedLayout() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    let laysOutWide = tracker.columnChanged(to: wide)
    #expect(laysOutWide, "the storage was laid out at this column, so it can be laid out again now")
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
  }

  @Test func aDocumentInstalledBeforeAnyColumnIsLaidOutAtTheFirstOne() {
    var tracker = ReadingPlaceTracker()
    tracker.installed(atColumn: nil)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == nil)
    let laysOutWide = tracker.columnChanged(to: wide)
    #expect(laysOutWide)
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
  }

  /// At the document's end a restore clamps, so the line holding the place is not
  /// the one at the top. Tracking that line would walk the place back on every
  /// resize; until the reader scrolls, the place is the one that was carried.
  @Test func keepsTheCarriedPlaceUntilTheReaderScrollsAwayFromTheRestore() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    tracker.installed(atColumn: narrow)
    tracker.restored(top: 280)
    tracker.report(
      viewportTop: 280, line: NSRange(location: 200, length: 40), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    tracker.report(
      viewportTop: 260, line: NSRange(location: 160, length: 40), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 30)))
  }

  @Test func aViewportAboveTheTextIsTheTop() {
    var tracker = reading()
    tracker.report(viewportTop: -40, line: NSRange(location: 0, length: 60), in: index, length: 500)
    #expect(tracker.place == .top)
  }

  /// A jump is where the reader is, even while tracking waits for a rebuild.
  @Test func aJumpIsThePlaceEvenWhilePaused() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    tracker.jumped(to: ReadingPlace(anchor: "section-2", offset: 0))
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-2", offset: 0)))
  }
}
