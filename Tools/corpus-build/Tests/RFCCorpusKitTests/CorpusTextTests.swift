import Testing

@Suite struct CorpusTextTests {
  @Test func `an unreadable index reports its parse error, not a missing variable`() throws {
    let index = try #require(CorpusText.parseIndex(atPath: "/nonexistent/rfc-index.xml"))
    do {
      _ = try index.get()
      Issue.record("an index that does not exist parsed")
    } catch {
      #expect(!(error is CorpusTextError))
    }
  }

  @Test(.disabled(if: CorpusText.hasIndex, "RFC_CORPUS_INDEX is set"))
  func `an index that is not set is reported as RFC_CORPUS_INDEX`() {
    #expect(CorpusText.parseIndex(atPath: nil) == nil)
    #expect(CorpusText.parseIndex(atPath: "") == nil)
    do {
      _ = try CorpusText.index()
      Issue.record("an index that is not set was read")
    } catch {
      #expect((error as? CorpusTextError)?.description == "RFC_CORPUS_INDEX is not set")
    }
  }
}

/// A document fetched locally, by `make corpus`, but not on the Makefile's list is
/// refused before its file is looked for: CI fetches only the listed ones (#986).
@Suite(
  "Corpus-backed: unlisted documents",
  .enabled(if: CorpusText.isAvailable && CorpusText.listedDocuments != nil))
struct CorpusBackedUnlistedDocumentTests {
  @Test func `a document not on the list is refused as not listed`() {
    do {
      _ = try CorpusText.text("rfc0")
      Issue.record("a document not on the list was read")
    } catch {
      #expect(
        (error as? CorpusTextError)?.description
          == "rfc0 is read by a corpus-backed test but not listed: add it to CORPUS_TEST_DOCUMENTS")
    }
  }
}
