import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// Which of a draft's two forms its header is read from. The fetch is a closure over
/// the extension, answering nil where the archive has no such file; the bodies are
/// hand-written in the shape of a draft header.
@Suite("Draft source")
struct DraftSourceTests {
  private static let xml = Data(#"<rfc obsoletes="9990"><front/></rfc>"#.utf8)
  private static let text = Data("Internet-Draft\nUpdates: 9991 (if approved)\n".utf8)
  /// Cut off before its root element starts. Cut inside the root's start tag instead,
  /// libxml2 on Linux recovers and reports the root anyway, where Apple's parser does
  /// not, so the XML would parse on one platform and not the other.
  private static let broken = Data("<?xml version=\"1.0\"?>\n<!-- cut off".utf8)

  /// Records what was asked for, one extension at a time.
  private actor Archive {
    let files: [String: Data]
    private(set) var asked: [String] = []

    init(_ files: [String: Data]) {
      self.files = files
    }

    func fetch(_ pathExtension: String) -> Data? {
      asked.append(pathExtension)
      return files[pathExtension]
    }
  }

  @Test func `a draft with XML is read from it, and its text is not fetched`() async throws {
    let archive = Archive(["xml": Self.xml, "txt": Self.text])
    let header = try await DraftSource.header { await archive.fetch($0) }
    #expect(header == DraftHeader(obsoletes: [9990]))
    #expect(await archive.asked == ["xml"])
  }

  @Test func `a draft without XML is read from its text`() async throws {
    let archive = Archive(["txt": Self.text])
    #expect(
      try await DraftSource.header { await archive.fetch($0) } == DraftHeader(updates: [9991]))
  }

  /// Otherwise the draft fails every run and never appears.
  @Test func `XML that does not parse falls back to the text`() async throws {
    let archive = Archive(["xml": Self.broken, "txt": Self.text])
    #expect(
      try await DraftSource.header { await archive.fetch($0) } == DraftHeader(updates: [9991]))
  }

  @Test func `a draft with neither is an error`() async throws {
    let archive = Archive([:])
    await #expect(throws: DraftSource.Missing.self) {
      try await DraftSource.header { await archive.fetch($0) }
    }
  }
}
