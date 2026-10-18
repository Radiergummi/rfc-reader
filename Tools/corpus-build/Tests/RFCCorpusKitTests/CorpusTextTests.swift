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

  @Test func `an index that is not set is reported as RFC_CORPUS_INDEX`() {
    #expect(CorpusText.parseIndex(atPath: nil) == nil)
    #expect(CorpusTextError.indexNotConfigured.description == "RFC_CORPUS_INDEX is not set")
  }
}
