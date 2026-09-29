import Foundation
import RFCCorpusKit
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
    #expect(Set(object.keys) == ["version", "files"])
  }
}
