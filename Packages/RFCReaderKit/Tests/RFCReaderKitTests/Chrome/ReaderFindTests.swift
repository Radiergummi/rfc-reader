import Testing

@testable import RFCReaderKit

/// Find is offered only while a text view shows (#943): the rendered document, or
/// the original text once it is here. A published original's page, and Original
/// Text while it loads or after it failed to, have nothing to search.
@Suite("Reader find")
struct ReaderFindTests {
  @Test func `the rendered document is searched`() {
    #expect(
      ReaderFind.isAvailable(
        hasDocument: true, publishedOriginal: nil, showsOriginal: false, hasOriginalText: false))
  }

  @Test func `nothing is searched before the document is here`() {
    #expect(
      !ReaderFind.isAvailable(
        hasDocument: false, publishedOriginal: nil, showsOriginal: false, hasOriginalText: false))
  }

  /// The text loaded and says only where the original is, so the page shows instead.
  @Test func `a pointer's page is not searched`() {
    #expect(
      !ReaderFind.isAvailable(
        hasDocument: true, publishedOriginal: .pointer, showsOriginal: false,
        hasOriginalText: false))
  }

  /// Original Text shows a pointer as published, in a text view.
  @Test func `a pointer's original text is searched once it is here`() {
    #expect(
      ReaderFind.isAvailable(
        hasDocument: true, publishedOriginal: .pointer, showsOriginal: true, hasOriginalText: true))
  }

  /// A scan's page comes before Original Text, in either mode.
  @Test func `a scan's page is not searched in either mode`() {
    for showsOriginal in [false, true] {
      for hasText in [false, true] {
        #expect(
          !ReaderFind.isAvailable(
            hasDocument: hasText, publishedOriginal: .scan, showsOriginal: showsOriginal,
            hasOriginalText: hasText))
      }
    }
  }

  @Test func `the original text is searched once it is here`() {
    #expect(
      ReaderFind.isAvailable(
        hasDocument: false, publishedOriginal: nil, showsOriginal: true, hasOriginalText: true))
  }

  /// Loading, or failed to load: a progress view or an error, whether the rendered
  /// document is here or not.
  @Test func `the original text is not searched until it is here`() {
    for hasDocument in [false, true] {
      #expect(
        !ReaderFind.isAvailable(
          hasDocument: hasDocument, publishedOriginal: nil, showsOriginal: true,
          hasOriginalText: false))
    }
  }
}
