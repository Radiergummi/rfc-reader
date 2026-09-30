import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Packet presentation")
struct PacketPresentationTests {
  private func decorated(_ text: String) throws -> DecoratedText {
    let rendition = try #require(PacketPresentation.render(text))
    guard case .decorated(let decorated) = rendition else {
      Issue.record("a packet renders as decorated text")
      throw CancellationError()
    }
    return decorated
  }

  private func point(_ x: Int, _ y: Int) -> GridPoint { GridPoint(x: x, y: y) }

  @Test func `a packet's grid becomes one stroke per side of its only field`() throws {
    let strokes = Set(try decorated(PacketSamples.hyphenated).strokes)
    #expect(
      strokes == [
        Stroke(start: point(7, 5), end: point(71, 5), style: .solid),
        Stroke(start: point(7, 13), end: point(71, 13), style: .solid),
        Stroke(start: point(7, 5), end: point(7, 13), style: .solid),
        Stroke(start: point(71, 5), end: point(71, 13), style: .solid),
      ])
  }

  @Test func `only the characters that draw the grid are hidden`() throws {
    let text = PacketSamples.hyphenated as NSString
    let hidden = try decorated(PacketSamples.hyphenated).hidden
    #expect(hidden.count == PacketDiagram.layout(of: PacketSamples.hyphenated)?.marks.count)
    for range in hidden {
      #expect("+-=|".contains(text.substring(with: range)), "hid \(text.substring(with: range))")
    }
    let hyphen = text.range(of: "Hyphen-")
    let nameHyphen = NSRange(location: NSMaxRange(hyphen) - 1, length: 1)
    #expect(!hidden.contains(nameHyphen), "the hyphen in the name stays visible")
  }

  @Test func `the bit ruler is set in the secondary color`() throws {
    let lines = PacketSamples.hyphenated.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(
      try decorated(PacketSamples.hyphenated).secondary == [
        NSRange(location: 0, length: lines[0].utf16.count),
        NSRange(location: lines[0].utf16.count + 1, length: lines[1].utf16.count),
      ])
  }

  @Test func `a variable-length field's edge is dashed`() throws {
    let strokes = try decorated(PacketSamples.variable).strokes
    #expect(strokes.contains(Stroke(start: point(7, 5), end: point(7, 9), style: .solid)))
    #expect(strokes.contains(Stroke(start: point(7, 9), end: point(7, 13), style: .dashed)))
  }

  @Test func `a name with a combining mark still hides the delimiter after it`() throws {
    let text = PacketSamples.combining as NSString
    for range in try decorated(PacketSamples.combining).hidden {
      #expect("+-|".contains(text.substring(with: range)), "hid \(text.substring(with: range))")
    }
  }

  @Test func `a caption after the diagram is neither hidden nor drawn over`() throws {
    let text = PacketSamples.captioned as NSString
    let caption = text.range(of: "Figure 1")
    let decorated = try decorated(PacketSamples.captioned)
    #expect(decorated.hidden.allSatisfy { NSMaxRange($0) <= caption.location })
    #expect(decorated.strokes.allSatisfy { $0.end.y <= 2 * 7 }, "the grid ends on line 6")
  }

  @Test func `text that is not a packet diagram is declined`() {
    #expect(PacketPresentation.render("+---+\n| A |\n+---+") == nil)
  }

  @Test func `the delimiter after a name with a combining mark is among the hidden`() throws {
    let text = PacketSamples.combining as NSString
    let decorated = try decorated(PacketSamples.combining)
    #expect(
      decorated.hidden.count == PacketDiagram.layout(of: PacketSamples.combining)?.marks.count)
    let name = text.range(of: "Le\u{0302}ngth")
    let delimiter = text.range(
      of: "|", range: NSRange(location: NSMaxRange(name), length: text.length - NSMaxRange(name)))
    #expect(decorated.hidden.contains(delimiter))
  }

  /// A character set two cells wide in a monospaced font counts as one column, so
  /// the lines after it would land a cell off their borders on the rest of its row.
  @Test func `a diagram with a double-width character is declined`() {
    let wide = PacketSamples.variable.replacingOccurrences(of: "Type", with: "Ty\u{6F22}e")
    #expect(PacketDiagram.layout(of: wide) != nil, "the recognizer still reads it")
    #expect(PacketPresentation.render(wide) == nil)
  }
}
