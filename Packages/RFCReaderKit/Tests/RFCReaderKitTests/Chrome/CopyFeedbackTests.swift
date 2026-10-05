import Foundation
import Testing

@testable import RFCReaderKit

/// What VoiceOver says once a copy worked (#777): what was copied, since a menu
/// closing says nothing.
@Suite("Copy feedback")
struct CopyFeedbackTests {
  @Test func `each copy is announced as what it copied`() {
    #expect(CopyFeedback.citation.announcement(in: .english) == "Citation copied")
    #expect(CopyFeedback.link.announcement(in: .english) == "Link copied")
    #expect(CopyFeedback.figure.announcement(in: .english) == "Figure copied")
    #expect(CopyFeedback.quote.announcement(in: .english) == "Quote copied")
    #expect(CopyFeedback.checklist.announcement(in: .english) == "Checklist copied")
    #expect(CopyFeedback.code.announcement(in: .english) == "Code copied")
  }
}
