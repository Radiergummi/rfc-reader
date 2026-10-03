import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// The manifest is what the app checks a downloaded pack against, so its digests
/// have to be SHA-256 as anyone else computes it, in lowercase hex (#163). The
/// vectors are FIPS 180-4's own examples.
@Suite("Manifest")
struct ManifestTests {
  private func digest(_ string: String) -> String {
    Manifest.Entry(path: "file", data: Data(string.utf8)).sha256
  }

  @Test func `an empty file has the empty digest`() {
    #expect(digest("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }

  @Test func `a short file has the standard's one block digest`() {
    #expect(digest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  /// Longer than one 64-byte block once padded, so the digest runs over two.
  @Test func `a file longer than a block has the standard's two block digest`() {
    #expect(
      digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  }

  @Test func `an entry records the file's size`() {
    #expect(Manifest.Entry(path: "a/b.xml", data: Data(count: 1234)).bytes == 1234)
  }

  /// Nothing of the run it was written in, so a rebuild of the same files can be
  /// compared with the release byte for byte.
  @Test func `a manifest holds its version and files and nothing else`() throws {
    let manifest = Manifest(
      version: "2026.09", files: [Manifest.Entry(path: "rfc1.xml", data: Data("x".utf8))])
    let encoded = try JSONEncoder().encode(manifest)
    let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(Set(object.keys) == ["version", "files", "skipped"])
  }

  /// The documents a pack leaves out on purpose, so the app knows without the
  /// network what it would otherwise only learn from their text (#316).
  @Test func `a manifest names each document it skips and why`() throws {
    let manifest = Manifest(
      version: "2026.09", files: [],
      skipped: [Manifest.Skip(document: "rfc1119", reason: .publishedOnlyAsPDF)])
    let encoded = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
    #expect(encoded.contains(#""document":"rfc1119""#))
    #expect(encoded.contains(#""reason":"published-only-as-pdf""#))
    #expect(try JSONDecoder().decode(Manifest.self, from: Data(encoded.utf8)) == manifest)
  }

  /// The skips are the convert run's, read from its report, in its order.
  @Test func `the skipped documents are the report's`() throws {
    let empty = RFCDocument(header: DocumentHeader(title: ""), sections: [], source: .text)
    func report(_ id: String, skipped: Manifest.SkipReason?) -> DocumentReport {
      var report = DocumentReport(document: empty, id: id)
      report.skipped = skipped
      return report
    }
    let converted = report("rfc1149", skipped: nil)
    let first = report("rfc570", skipped: .publishedOnlyAsPDF)
    let second = report("rfc1119", skipped: .publishedOnlyAsPDF)
    let report = try JSONEncoder().encode([first, converted, second])
    #expect(
      try Manifest.skips(inReport: report) == [
        Manifest.Skip(document: "rfc570", reason: .publishedOnlyAsPDF),
        Manifest.Skip(document: "rfc1119", reason: .publishedOnlyAsPDF),
      ])
  }
}
