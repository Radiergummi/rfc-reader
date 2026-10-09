import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A numbered heading's number hangs in the gutter, a link to its own heading,
/// where the window leaves room for it (#433).
@Suite("Builder: hanging section numbers")
struct SectionNumberHangTests {
  private var document: RFCDocument {
    RFCDocument(
      header: DocumentHeader(title: "T", abstract: [.paragraph(Paragraph(text: "About."))]),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Introduction",
          blocks: [.paragraph(Paragraph(text: "Prose."))],
          subsections: [
            Section(
              anchor: "section-1.1", number: "1.1", title: "Requirements Notation",
              blocks: [
                .list(ListBlock(style: .bullet, items: [ListItem(text: "Item.")]))
              ])
          ]),
        Section(
          anchor: "acknowledgements", title: "Acknowledgements",
          blocks: [.paragraph(Paragraph(text: "Thanks."))]),
        Section(
          anchor: "appendix-A", number: "A", title: "Collected Grammar",
          subsections: [
            Section(anchor: "appendix-A.10.2", number: "A.10.2", title: "Deep", isAppendix: true)
          ],
          isAppendix: true),
      ],
      source: .xml)
  }

  private var hanging: ReadingStyle {
    var style = ReadingStyle()
    style.sectionNumberHang = SectionNumberHang.width(of: document, style: style)
    return style
  }

  private func paragraphStyle(at offset: Int, in text: NSAttributedString) throws
    -> NSParagraphStyle
  {
    try #require(
      text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
  }

  // MARK: The hang's width

  @Test func `the hang is the widest number in its heading's font, and the gap`() {
    let style = ReadingStyle()
    let narrow = DocumentTextBuilder.lineWidth(
      NSAttributedString(string: "1", attributes: [.font: style.headingFont(depth: 1)]))
    let wide = DocumentTextBuilder.lineWidth(
      NSAttributedString(string: "A.10.2", attributes: [.font: style.headingFont(depth: 2)]))
    let hang = SectionNumberHang.width(of: document, style: style)
    #expect(abs(hang - (max(narrow, wide) + SectionNumberHang.gap(style: style))) < 0.001)
    #expect(hang > wide)
  }

  @Test func `a document without a numbered heading has no hang`() {
    let unnumbered = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [Section(anchor: "notes", title: "Notes")], source: .xml)
    #expect(SectionNumberHang.width(of: unnumbered, style: ReadingStyle()) == 0)
  }

  @Test func `a bibliography's number does not widen the hang`() {
    let withReferences = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(anchor: "section-1", number: "1", title: "One"),
        Section(
          anchor: "section-10.20.30", number: "10.20.30", title: "References",
          blocks: [.references(ReferenceList(title: "References", entries: []))]),
      ],
      source: .xml)
    let one = SectionNumberHang.width(
      of: RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [Section(anchor: "section-1", number: "1", title: "One")], source: .xml),
      style: ReadingStyle())
    #expect(SectionNumberHang.width(of: withReferences, style: ReadingStyle()) == one)
  }

  // MARK: Whether there is room

  @Test func `numbers hang where the gutter keeps a margin beside them`() {
    let hang: CGFloat = 40
    // A gutter of exactly margin + hang: room, just.
    let width = ReaderLayout.idealMeasure + 2 * (ReaderLayout.margin + hang)
    #expect(ReaderLayout.hangs(hang, width: width, measure: .recommended))
    #expect(!ReaderLayout.hangs(hang, width: width - 2, measure: .recommended))
  }

  @Test func `full width and a phone's column leave no room`() {
    #expect(!ReaderLayout.hangs(30, width: 2000, measure: .fullWidth))
    #expect(!ReaderLayout.hangs(30, width: 390, measure: .recommended))
  }

  @Test func `no hang needs no room`() {
    #expect(!ReaderLayout.hangs(0, width: 2000, measure: .recommended))
  }

  @Test func `the container reaches into the gutter by the hang`() {
    #expect(ReaderLayout.containerReach(gutter: 100, hang: 40) == 40)
    #expect(ReaderLayout.containerReach(gutter: 100, hang: 0) == 0)
  }

  /// Until the rebuild lands: the container may reach no further than the gutter,
  /// on the leading side for the numbers and on the trailing side for the text.
  @Test func `a gutter narrowed under the hang before the rebuild keeps the text in view`() {
    #expect(
      ReaderLayout.containerReach(gutter: ReaderLayout.margin, hang: 60) == ReaderLayout.margin)
  }

  // MARK: The build

  @Test func `a build that hangs says how far`() {
    let built = DocumentTextBuilder.build(document, style: hanging)
    // Within a rounding: two measurements of a line can differ in the last places.
    #expect(
      abs(built.sectionNumberHang - SectionNumberHang.width(of: document, style: hanging)) < 0.001)
    #expect(DocumentTextBuilder.build(document, style: ReadingStyle()).sectionNumberHang == 0)
  }

  @Test func `a hung number is a link to its heading in the secondary color`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let heading = try Fixtures.offset(of: "\t1.1\tRequirements Notation\n", in: built.text)
    let number = heading + 1
    let link = try #require(built.text.attribute(.link, at: number, effectiveRange: nil) as? URL)
    #expect(DocumentTextBuilder.anchor(from: link) == "section-1.1")
    let color = built.text.attribute(.foregroundColor, at: number, effectiveRange: nil)
    #expect(color as? PlatformColor == RFCColors.secondaryLabel)
    var range = NSRange()
    let marked = built.text.attribute(.rfcSectionNumber, at: number, effectiveRange: &range)
    #expect(marked as? String == "section-1.1")
    #expect((built.text.string as NSString).substring(with: range) == "1.1")
    // The title is the heading's, in its color, and no link.
    let title = heading + "\t1.1\t".utf16.count
    #expect(built.text.attribute(.link, at: title, effectiveRange: nil) == nil)
    let titleColor = built.text.attribute(.foregroundColor, at: title, effectiveRange: nil)
    #expect(titleColor as? PlatformColor == RFCColors.label)
  }

  @Test func `the number under an offset is found with its heading and its extent`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let heading = try Fixtures.offset(of: "\t1.1\tRequirements Notation\n", in: built.text)
    let found = try #require(built.text.sectionNumber(at: heading + 2))
    #expect(found.anchor == "section-1.1")
    #expect(found.range == NSRange(location: heading + 1, length: 3))
    #expect(built.text.sectionNumber(at: heading) == nil, "the tab before it is not the number")
    #expect(built.text.sectionNumber(at: heading + 5) == nil, "nor is the title")
  }

  @Test func `a hung heading copies as the heading reads inline`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    for (hung, copied) in [
      ("\t1.1\tRequirements Notation\n", "1.1. Requirements Notation\n"),
      ("\tA\tCollected Grammar\n", "Appendix A. Collected Grammar\n"),
    ] {
      let start = try Fixtures.offset(of: hung, in: built.text)
      let whole = NSRange(location: start, length: hung.utf16.count)
      #expect(SelectionText.plainText(of: built.text.attributedSubstring(from: whole)) == copied)
      // Part of the number is the whole prefix, as part of a chip is its label.
      let fromNumber = NSRange(location: start + 2, length: hung.utf16.count - 2)
      #expect(
        SelectionText.plainText(of: built.text.attributedSubstring(from: fromNumber)) == copied)
    }
  }

  @Test func `a copy ending inside the number gets the heading's prefix, not the number's link`()
    throws
  {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let start = try Fixtures.offset(of: "\t1.1\tRequirements Notation\n", in: built.text)
    // From the paragraph before, to the middle of `1.1`.
    let selection = NSRange(location: start - 3, length: 5)
    let rich = SelectionText.richCopy(
      of: built.text.attributedSubstring(from: selection), publicURL: { $0 })
    let prefix = try #require(rich.string.range(of: "1.1. "))
    let offset = NSRange(prefix, in: rich.string).location
    #expect(rich.attribute(.link, at: offset, effectiveRange: nil) == nil)
    #expect(rich.attribute(.rfcSectionNumber, at: offset, effectiveRange: nil) == nil)
    let color = rich.attribute(.foregroundColor, at: offset, effectiveRange: nil)
    #expect(color as? PlatformColor == RFCColors.label)
  }

  /// The hang is the screen's: a paste is indented as the text is where no number
  /// hangs, whatever the window's width was.
  @Test func `a rich copy is indented as if nothing hung`() throws {
    func copy(_ built: BuiltDocument) -> NSAttributedString {
      SelectionText.richCopy(
        of: built.text, publicURL: { $0 }, hang: built.sectionNumberHang)
    }
    let hung = copy(DocumentTextBuilder.build(document, style: hanging))
    let plain = copy(DocumentTextBuilder.build(document, style: ReadingStyle()))
    for text in ["Prose.", "Item.", "Requirements Notation"] {
      let copied = try paragraphStyle(at: try Fixtures.offset(of: text, in: hung), in: hung)
      let unhung = try paragraphStyle(at: try Fixtures.offset(of: text, in: plain), in: plain)
      #expect(copied.firstLineHeadIndent == unhung.firstLineHeadIndent, "\(text)")
      #expect(copied.headIndent == unhung.headIndent, "\(text)")
    }
    let item = try Fixtures.offset(of: "Item.", in: hung)
    #expect(
      try paragraphStyle(at: item, in: hung).tabStops.map(\.location)
        == paragraphStyle(at: try Fixtures.offset(of: "Item.", in: plain), in: plain).tabStops.map(
          \.location))
  }

  @Test func `an appendix hangs its letter`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let heading = try Fixtures.offset(of: "\tA\tCollected Grammar\n", in: built.text)
    let marked = built.text.attribute(.rfcSectionNumber, at: heading + 1, effectiveRange: nil)
    #expect(marked as? String == "appendix-A")
  }

  @Test func `the number hangs flush against the column and the title starts on it`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let hang = built.sectionNumberHang
    let heading = try Fixtures.offset(of: "\t1\tIntroduction\n", in: built.text)
    let style = try paragraphStyle(at: heading, in: built.text)
    #expect(style.firstLineHeadIndent == 0)
    #expect(style.headIndent == hang, "a wrapped title stays on the column")
    #expect(style.tabStops.map(\.alignment) == [.right, .left])
    #expect(
      style.tabStops.map(\.location) == [hang - SectionNumberHang.gap(style: hanging), hang])
  }

  @Test func `an unnumbered heading stays as it is, on the column`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let heading = try Fixtures.offset(of: "Acknowledgements\n", in: built.text)
    #expect(built.text.attribute(.rfcSectionNumber, at: heading, effectiveRange: nil) == nil)
    #expect(built.text.attribute(.link, at: heading, effectiveRange: nil) == nil)
    let style = try paragraphStyle(at: heading, in: built.text)
    #expect(style.firstLineHeadIndent == built.sectionNumberHang)
  }

  /// The container is wider than the column by the hang, on the leading side, so
  /// every paragraph is set in by it: the text still wraps at the column.
  @Test func `every paragraph is set in by the hang`() throws {
    let built = DocumentTextBuilder.build(document, style: hanging)
    let hang = built.sectionNumberHang
    let headings = Set(
      try [
        "\t1\tIntroduction\n", "\t1.1\tRequirements Notation\n", "\tA\tCollected Grammar\n",
        "\tA.10.2\tDeep\n",
      ].map { try Fixtures.offset(of: $0, in: built.text) })
    let string = built.text.string as NSString
    var paragraphs: [(style: NSParagraphStyle, setsTabs: Bool)] = []
    built.text.enumerateAttribute(
      .paragraphStyle, in: NSRange(location: 0, length: built.text.length)
    ) { value, range, _ in
      let paragraph = string.paragraphRange(for: range)
      guard let style = value as? NSParagraphStyle, !headings.contains(paragraph.location) else {
        return
      }
      paragraphs.append((style, string.substring(with: paragraph).contains("\t")))
    }
    #expect(paragraphs.contains { $0.setsTabs }, "the list item tabs to its text")
    for (style, setsTabs) in paragraphs {
      #expect(style.headIndent >= hang)
      #expect(style.firstLineHeadIndent >= hang)
      // A paragraph with no tab keeps the system's stops, which nothing reaches.
      guard setsTabs else { continue }
      for stop in style.tabStops {
        #expect(stop.location >= hang)
      }
    }
  }

  @Test func `without the room a heading reads as it always has`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let heading = try Fixtures.offset(of: "1.1. Requirements Notation\n", in: built.text)
    #expect(built.text.attribute(.rfcSectionNumber, at: heading, effectiveRange: nil) == nil)
    #expect(try paragraphStyle(at: heading, in: built.text).firstLineHeadIndent == 0)
  }

  @Test func `paper never hangs a number`() throws {
    var paper = hanging
    paper.emitsLinks = false
    let built = DocumentTextBuilder.build(document, style: paper)
    #expect(built.sectionNumberHang == 0)
    _ = try Fixtures.offset(of: "1.1. Requirements Notation\n", in: built.text)
  }

  // MARK: Drawing and copying

  @Test func `a hung number keeps its own color, and the label's under the pointer`() throws {
    let url = try #require(
      DocumentTextBuilder.url("section-1", scheme: DocumentTextBuilder.anchorScheme))
    let defaults: [NSAttributedString.Key: Any] = [.foregroundColor: RFCColors.link]
    let resting = DocumentTextBuilder.linkRenderingAttributes(
      for: url, defaults: defaults, sectionNumber: .resting)
    #expect(resting[.foregroundColor] == nil, "the storage's secondary color shows")
    let hovered = DocumentTextBuilder.linkRenderingAttributes(
      for: url, defaults: defaults, sectionNumber: .hovered)
    #expect(hovered[.foregroundColor] as? PlatformColor == RFCColors.label)
    let link = DocumentTextBuilder.linkRenderingAttributes(for: url, defaults: defaults)
    #expect(link[.foregroundColor] as? PlatformColor == RFCColors.link)
  }

  @Test func `the copied badge sits just above the number, ending where it ends`() {
    let frame = FragmentGeometry.linkCopiedBadgeFrame(
      numberFrame: CGRect(x: 10, y: 100, width: 20, height: 18),
      badgeSize: CGSize(width: 80, height: 20), containerOrigin: CGPoint(x: 50, y: 30))
    #expect(frame.maxX == CGFloat(50 + 30))
    #expect(frame.maxY == CGFloat(30 + 100) - FragmentGeometry.badgeGap)
    #expect(frame.size == CGSize(width: 80, height: 20))
  }

  @Test func `the copied badge stays inside the view where the gutter is narrow`() {
    let frame = FragmentGeometry.linkCopiedBadgeFrame(
      numberFrame: CGRect(x: 10, y: 100, width: 20, height: 18),
      badgeSize: CGSize(width: 90, height: 20), containerOrigin: CGPoint(x: 30, y: 30))
    #expect(frame.minX == 0)
    #expect(frame.size == CGSize(width: 90, height: 20))
  }

  @Test func `the copied link is the RFC Editor's, to the section and to the appendix`() throws {
    for (anchor, fragment) in [("section-1.1", "section-1.1"), ("appendix-A", "appendix-A")] {
      let url = try #require(
        DocumentTextBuilder.url(anchor, scheme: DocumentTextBuilder.anchorScheme))
      let copy = try #require(
        LinkCopy.forLink(url, from: .rfc(9110), in: nil, bibliography: []))
      #expect(copy.url.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#\(fragment)")
    }
  }
}
