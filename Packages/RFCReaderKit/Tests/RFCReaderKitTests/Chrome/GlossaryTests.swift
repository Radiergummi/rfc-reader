import Foundation
import RFCKit
import RFCReaderKit
import Testing

/// The app's own explanations of the labels it shows (#362): every status, stream
/// and series, and the process terms. A label with no entry is a test failure here,
/// not a button that opens nothing.
@Suite("Glossary")
struct GlossaryTests {
  @Test func `every status, stream and series is a term`() {
    let terms = Set(Glossary.Term.allCases)
    for status in PublicationStatus.allCases { #expect(terms.contains(.status(status))) }
    for stream in PublicationStream.allCases { #expect(terms.contains(.stream(stream))) }
    for series in DocumentID.Series.allCases { #expect(terms.contains(.series(series))) }
    for term in Glossary.ProcessTerm.allCases { #expect(terms.contains(.process(term))) }
  }

  /// Two to four sentences, written out: a title and an explanation, each ending as
  /// a sentence does.
  @Test(arguments: Glossary.Term.allCases)
  func `every entry is a title and two to four sentences`(term: Glossary.Term) {
    let entry = Glossary.entry(for: term)
    #expect(!entry.title.isEmpty)
    #expect((2...4).contains(Self.sentences(in: entry.explanation)), "\(entry.explanation)")
    #expect(entry.explanation.hasSuffix("."))
  }

  /// A related term opens its own entry, so it has to be another term, and once.
  @Test(arguments: Glossary.Term.allCases)
  func `every related term is another term, named once`(term: Glossary.Term) {
    let related = Glossary.entry(for: term).related
    #expect(!related.contains(term))
    #expect(Set(related).count == related.count)
  }

  /// No entry is an island: each points somewhere further.
  @Test(arguments: Glossary.Term.allCases)
  func `every entry names a related term`(term: Glossary.Term) {
    #expect(!Glossary.entry(for: term).related.isEmpty)
  }

  /// What a list row's tooltip and the Info pane's status box say: a sentence or two
  /// the explanation opens with, so the box and the popover agree.
  @Test(arguments: Glossary.Term.allCases)
  func `a summary is a sentence or two the explanation opens with`(term: Glossary.Term) {
    let entry = Glossary.entry(for: term)
    #expect(entry.explanation.hasPrefix(entry.summary + " "))
    #expect((1...2).contains(Self.sentences(in: entry.summary)))
    #expect(entry.summary.hasSuffix("."))
  }

  /// A status's title is the name the app shows for it, so the popover opens on the
  /// word that was clicked.
  @Test(arguments: PublicationStatus.allCases)
  func `a status's entry is titled with its name`(status: PublicationStatus) {
    #expect(Glossary.entry(for: .status(status)).title == status.displayName)
  }

  /// Sentences end in a full stop and a space, or at the end; the entries use no
  /// abbreviation with a full stop in it, which this would count as an end.
  private static func sentences(in text: String) -> Int {
    text.components(separatedBy: ". ").count
  }
}
