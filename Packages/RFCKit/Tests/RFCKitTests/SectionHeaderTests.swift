import Testing

@testable import RFCKit

/// A section running header's first sighting opens its section only where the
/// document does not head that section itself nearby: on the header's page or the
/// page before it (#291, #57). Hand-written lines in the shape of an RFC's pages.
@Suite("Section running headers")
struct SectionHeaderTests {
  private typealias Line = LegacyTextParser.Line

  /// A page: its header block, a blank line, then its body.
  private func page(header: String? = nil, _ body: [String]) -> [Line] {
    var lines: [Line] = []
    if let header { lines += [.sectionHeader(header), .text("")] }
    return lines + body.map(Line.text) + [.text(""), .pageBreak]
  }

  private func headsNearby(_ lines: [Line]) -> Bool {
    let index = lines.firstIndex {
      if case .sectionHeader = $0 { true } else { false }
    }!
    guard case .sectionHeader(let header) = lines[index] else { return false }
    return LegacyTextParser.headsNearby(
      header, at: index, in: lines, bodyIsIndented: true, colonNumbered: false)
  }

  /// The section starts at the head of one page, whose header still names the last
  /// one, and its own name first runs on the next.
  @Test func `a heading on the page before heads the section`() {
    let lines =
      page(["4.  Retry Handling", "", "   A sender waits before it sends again."])
      + page(header: "Retry Handling", ["   The wait doubles each time."])
    #expect(headsNearby(lines))
  }

  /// Centered, as some documents set their chapter headings: still the document's own.
  @Test func `a centered numbered heading heads the section`() {
    let lines =
      page(["                     4.  RETRY HANDLING", "", "   A sender waits."])
      + page(header: "Retry Handling", ["   The wait doubles each time."])
    #expect(headsNearby(lines))
  }

  @Test func `a heading on the same page heads the section`() {
    let lines = page(header: "Retry Handling", ["4.  Retry Handling", "", "   A sender waits."])
    #expect(headsNearby(lines))
  }

  /// A number in the header is part of what it says, not a page number to mask:
  /// compared as the heading reads, the two agree (#57).
  @Test func `a header with a number in it matches its heading`() {
    let lines =
      page(["4.  Phase 2 Exchange", "", "   Its round follows the first."])
      + page(header: "Phase 2 Exchange", ["   It carries the keys."])
    #expect(headsNearby(lines))
  }

  /// The same words headed pages away speak for nothing here: this header is the
  /// only thing saying where its section starts.
  @Test func `a heading further away does not head the section`() {
    let lines =
      page(["2.  Retry Handling", "", "   Named here in passing."])
      + page(["   Other matters."])
      + page(["   More of them."])
      + page(header: "Retry Handling", ["   The list of entries."])
    #expect(!headsNearby(lines))
  }

  /// A heading of other words on the page is another section's.
  @Test func `a heading of other words does not head the section`() {
    let lines =
      page(["4.  Timers", "", "   A sender keeps two."])
      + page(header: "Retry Handling", ["   The wait doubles each time."])
    #expect(!headsNearby(lines))
  }
}
