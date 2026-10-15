import Foundation
import RFCKit

/// How the search's "In the text" rows say what the full-text search found (#37).
public enum SectionResults {
  /// "Searched 37 of 9,842 RFCs": how much of the corpus the index holds, so a missing
  /// hit does not read as "no RFC says this". The noun follows the total.
  public static func searched(_ searched: Int, of total: Int, locale: Locale = .interface)
    -> String
  {
    String(kit: "Searched \(searched) of \(total) RFCs", locale: locale)
  }

  /// `snippet`'s text, its matched words bold. A match ending inside a character, as
  /// one may (`Snippet.matches`), makes the whole character bold.
  public static func attributed(_ snippet: Snippet) -> AttributedString {
    var attributed = AttributedString(snippet.text)
    for match in snippet.matches {
      let whole = snippet.text.rangeOfComposedCharacterSequences(for: match)
      guard let range = Range(whole, in: attributed) else { continue }
      attributed[range].inlinePresentationIntent = .stronglyEmphasized
    }
    return attributed
  }
}
