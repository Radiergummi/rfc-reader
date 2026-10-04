import Testing

@testable import RFCReaderKit

/// What VoiceOver says once a copy worked (#777): what was copied, since a menu
/// closing says nothing.
@Suite("Copy feedback")
struct CopyFeedbackTests {
  @Test func `each copy is announced as what it copied`() {
    #expect(CopyFeedback.citation.announcement == "Citation copied")
    #expect(CopyFeedback.link.announcement == "Link copied")
    #expect(CopyFeedback.figure.announcement == "Figure copied")
    #expect(CopyFeedback.quote.announcement == "Quote copied")
    #expect(CopyFeedback.checklist.announcement == "Checklist copied")
    #expect(CopyFeedback.code.announcement == "Code copied")
  }
}
