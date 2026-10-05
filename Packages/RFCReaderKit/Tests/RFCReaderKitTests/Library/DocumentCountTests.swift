import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Document count")
struct DocumentCountTests {
  @Test func `one document is singular`() {
    #expect(DocumentCount.label(1, locale: Locale(identifier: "en_US")) == "1 Document")
  }

  @Test func `no documents are plural`() {
    #expect(DocumentCount.label(0, locale: Locale(identifier: "en_US")) == "0 Documents")
  }

  /// The whole series, grouped as the reader's locale groups it.
  @Test func `large counts are grouped by locale`() {
    #expect(DocumentCount.label(9842, locale: Locale(identifier: "en_US")) == "9,842 Documents")
    #expect(DocumentCount.label(9842, locale: Locale(identifier: "de_DE")) == "9.842 Dokumente")
  }

  @Test func `one document is singular in German too`() {
    #expect(DocumentCount.label(1, locale: Locale(identifier: "de_DE")) == "1 Dokument")
  }
}
