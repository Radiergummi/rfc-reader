import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// How the search's "In the text" rows say what they found (#37).
@Suite("Section results")
struct SectionResultsTests {
  private func boldRuns(of attributed: AttributedString) -> [String] {
    var runs: [String] = []
    for run in attributed.runs where run.inlinePresentationIntent == .stronglyEmphasized {
      runs.append(String(attributed[run.range].characters))
    }
    return runs
  }

  /// How much was searched, so a missing hit does not read as "no RFC says this".
  @Test func `the footer says how many RFCs were searched of how many`() {
    #expect(
      SectionResults.searched(37, of: 9_842, locale: Locale(identifier: "en_US"))
        == "Searched 37 of 9,842 RFCs")
    #expect(
      SectionResults.searched(37, of: 9_842, locale: Locale(identifier: "de_DE"))
        == "37 von 9.842 RFCs durchsucht")
  }

  /// The noun counts the RFCs there are, the second number.
  @Test func `the footer's noun follows the total`() {
    #expect(
      SectionResults.searched(1, of: 1, locale: Locale(identifier: "en_US"))
        == "Searched 1 of 1 RFC")
    #expect(
      SectionResults.searched(1, of: 2, locale: Locale(identifier: "en_US"))
        == "Searched 1 of 2 RFCs")
  }

  @Test func `a snippet's matches are bold and nothing else is`() {
    let text = "the congestion window grows"
    let snippet = Snippet(
      text: text, matches: [text.range(of: "congestion")!, text.range(of: "window")!])

    let attributed = SectionResults.attributed(snippet)
    #expect(String(attributed.characters) == text)
    let bold = boldRuns(of: attributed)
    #expect(bold == ["congestion", "window"])
  }

  /// A match may end before a combining mark (`Snippet.matches`): the whole
  /// character it ends inside is bold.
  @Test func `a match that ends inside a character makes the character bold`() {
    let text = "a foo\u{FE0F} bar"
    let end = text.unicodeScalars.index(text.startIndex, offsetBy: 5)
    let start = text.unicodeScalars.index(text.startIndex, offsetBy: 2)
    let attributed = SectionResults.attributed(Snippet(text: text, matches: [start..<end]))

    let bold = boldRuns(of: attributed)
    #expect(bold == ["foo\u{FE0F}"])
  }
}
