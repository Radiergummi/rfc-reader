import Foundation
import RFCReaderKit
import Testing

/// The app's own explanations of the labels it shows (#362). That every status,
/// stream and series has an entry is the compiler's to check, by the glossary's
/// exhaustive switches; these check the entries themselves.
@Suite("Glossary")
struct GlossaryTests {
  /// Two to four sentences, written out, and a title to open on.
  @Test(arguments: Glossary.Term.allCases)
  func `every entry is a title and two to four sentences`(term: Glossary.Term) {
    let entry = Glossary.entry(for: term, locale: .english)
    #expect(!entry.title.isEmpty)
    #expect((2...4).contains(Self.sentences(in: entry.explanation)), "\(entry.explanation)")
    #expect(entry.detail.hasSuffix("."))
  }

  /// What a list row's tooltip and the Info pane's status box say: a sentence or two,
  /// which the popover then goes on from.
  @Test(arguments: Glossary.Term.allCases)
  func `a summary is a sentence or two`(term: Glossary.Term) {
    let entry = Glossary.entry(for: term, locale: .english)
    #expect((1...2).contains(Self.sentences(in: entry.summary)), "\(entry.summary)")
    #expect(entry.summary.hasSuffix("."))
  }

  /// A related term opens its own entry, so it has to be another term, and once.
  @Test(arguments: Glossary.Term.allCases)
  func `every related term is another term, named once`(term: Glossary.Term) {
    let related = Glossary.entry(for: term, locale: .english).related
    #expect(!related.contains(term))
    #expect(Set(related).count == related.count)
  }

  /// No entry is an island: each points somewhere further, and every entry is pointed
  /// to from another, so "See also" reaches the whole glossary.
  @Test func `every entry names a related term and is named by one`() {
    let named = Set(
      Glossary.Term.allCases.flatMap { Glossary.entry(for: $0, locale: .english).related })
    for term in Glossary.Term.allCases {
      #expect(!Glossary.entry(for: term, locale: .english).related.isEmpty, "\(term)")
      #expect(named.contains(term), "nothing names \(term)")
    }
  }

  /// Sentences end in a full stop and a space, or at the end; the entries use no
  /// abbreviation with a full stop in it, which this would count as an end.
  private static func sentences(in text: String) -> Int {
    text.components(separatedBy: ". ").count
  }
}
