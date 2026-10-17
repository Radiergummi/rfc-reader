import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A translation's progress in a reader (#749): what the header says, and when one
/// is finished.
@Suite("Translation run")
struct TranslationRunTests {
  @Test func `a response is matched to its request by index, and nothing else`() {
    var run = TranslationRun(["one", "two"])
    _ = run.receive("eins", for: "0")
    _ = run.receive("drei", for: "7")
    _ = run.receive("vier", for: nil)
    #expect(run.received == ["one": "eins"])
    #expect(!run.isComplete)
    #expect(run.progress == 0.5)
    let lastMoved = run.receive("zwei", for: "1")
    #expect(lastMoved)
    #expect(run.isComplete)
  }

  /// A batch the framework ended early, as it does when its task is canceled, leaves
  /// English in the document, and is no translation.
  @Test func `a run is complete only once every request is back`() {
    var run = TranslationRun((0..<120).map(String.init))
    var steps = 0
    for index in 0..<100 {
      let moved = run.receive("x", for: String(index))
      if moved { steps += 1 }
    }
    #expect(steps == 2)
    #expect(!run.isComplete)
    #expect(TranslationRun([]).isComplete)
  }

  @Test func `the target is the reader's first language that is not English`() {
    #expect(DocumentTranslation.target(preferring: ["de-DE", "en-DE"])?.languageCode == .german)
    #expect(DocumentTranslation.target(preferring: ["en-GB", "fr-FR"])?.languageCode == .french)
    #expect(DocumentTranslation.target(preferring: ["en-US", "en-GB"]) == nil)
  }

  @Test func `the header says nothing of a translation the reader does not show`() {
    #expect(TranslationMark(.failed, showsTranslation: false, buildIsTranslation: false) == nil)
    #expect(
      TranslationMark(.idle, showsTranslation: true, buildIsTranslation: false)
        == .translating(progress: 0))
    #expect(
      TranslationMark(.failed, showsTranslation: true, buildIsTranslation: false) == .failed)
  }

  @Test func `a translation made is translating until its build is on screen`() throws {
    let translated = TranslatedDocument(try Fixtures.rfc2119(), [:])
    #expect(
      TranslationMark(.translated(translated), showsTranslation: true, buildIsTranslation: false)
        == .translating(progress: 1))
    #expect(
      TranslationMark(.translated(translated), showsTranslation: true, buildIsTranslation: true)
        == .translated)
  }
}
