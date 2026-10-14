import Foundation
import RFCKit

/// The defined terms the reader marks in a document (#396), and where in a run of
/// text they are used.
///
/// A use is the term as the document spells it, matched case-sensitively, as a whole
/// word: not inside a longer word or a hyphenated compound. Where two terms start at
/// the same word, the longer is the use, so `origin server` is one gloss, not `origin`.
/// A term of one word that is a common English word, `client` or `message`, is not
/// marked: every reader knows it, and it would be underlined in nearly every
/// paragraph. The common words are the lower-case words used in at least a tenth of
/// the corpus's documents, which `corpus-build common-words` measures; an acronym is
/// never one.
struct DefinedTermMatcher {
  /// The terms that may be marked, grouped by their first word, longest first.
  private let byFirstWord: [String: [DefinedTerm]]

  init(_ terms: [String: DefinedTerm], commonWords: Set<String> = Self.bundledCommonWords) {
    var byFirstWord: [String: [DefinedTerm]] = [:]
    for (spelling, term) in terms {
      let words = spelling.split(whereSeparator: \.isWhitespace)
      guard let first = words.first else { continue }
      if words.count == 1, commonWords.contains(spelling) { continue }
      byFirstWord[String(first), default: []].append(term)
    }
    self.byFirstWord = byFirstWord.mapValues {
      $0.sorted { $0.term.utf16.count > $1.term.utf16.count }
    }
  }

  var isEmpty: Bool { byFirstWord.isEmpty }

  /// A term, and the UTF-16 range of its use.
  typealias Use = (range: NSRange, term: DefinedTerm)

  /// The first use in `text` of each term not in `marked`, in order, as UTF-16 ranges.
  func uses(in text: String, skipping marked: Set<String>) -> [Use] {
    let string = text as NSString
    var marked = marked
    var found: [Use] = []
    var location = 0
    while location < string.length {
      let word = Self.word(in: string, at: location)
      guard word.length > 0 else {
        location += 1
        continue
      }
      let first = string.substring(with: word)
      let candidates = byFirstWord[first] ?? []
      if let term = candidates.first(where: { candidate in
        !marked.contains(candidate.term)
          && Self.isWholeWord(candidate.term, in: string, at: location)
      }) {
        let range = NSRange(location: location, length: term.term.utf16.count)
        found.append((range, term))
        marked.insert(term.term)
        location = NSMaxRange(range)
      } else {
        location = NSMaxRange(word)
      }
    }
    return found
  }

  /// The word starting at `location`, as `uses` reads words: letters and digits, with
  /// a hyphen inside one. Empty where no word starts there, which includes the middle
  /// of a word.
  private static func word(in string: NSString, at location: Int) -> NSRange {
    guard isWordCharacter(string, location), !isWordCharacter(string, location - 1),
      !isHyphen(string, location - 1)
    else { return NSRange(location: location, length: 0) }
    var end = location
    while isWordCharacter(string, end)
      || (isHyphen(string, end) && isWordCharacter(string, end + 1))
    {
      end += 1
    }
    return NSRange(location: location, length: end - location)
  }

  /// Whether `term` is written at `location` and ends a word there.
  private static func isWholeWord(_ term: String, in string: NSString, at location: Int) -> Bool {
    let length = term.utf16.count
    guard location + length <= string.length,
      string.substring(with: NSRange(location: location, length: length)) == term
    else { return false }
    let after = location + length
    return !isWordCharacter(string, after) && !isHyphen(string, after)
  }

  private static func isWordCharacter(_ string: NSString, _ location: Int) -> Bool {
    guard location >= 0, location < string.length,
      let scalar = Unicode.Scalar(string.character(at: location))
    else { return false }
    return CharacterSet.alphanumerics.contains(scalar)
  }

  private static func isHyphen(_ string: NSString, _ location: Int) -> Bool {
    location >= 0 && location < string.length && string.character(at: location) == 0x2D
  }

  /// The common words this package ships, `CommonWords.txt`, one per line.
  static let bundledCommonWords: Set<String> = {
    guard let url = Bundle.module.url(forResource: "CommonWords", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return Set(text.split(separator: "\n").map(String.init))
  }()
}
