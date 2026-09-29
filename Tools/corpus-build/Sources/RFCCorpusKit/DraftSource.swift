import Foundation
import RFCKit

/// Which of a draft's forms in the archive its header is read from: the XML where the
/// draft was submitted as XML and it parses, the text otherwise. XML that does not
/// parse falls back too, so such a draft is still read rather than failing every run.
public enum DraftSource {
  /// The archive has neither form of the revision.
  public struct Missing: Error {}

  /// - Parameter fetch: the revision's file with this extension, `xml` or `txt`, or
  ///   nil where the archive has none. Any other failure is thrown, not fallen back on.
  public static func header(
    fetch: (_ pathExtension: String) async throws -> Data?
  ) async throws -> DraftHeader {
    if let xml = try await fetch("xml"), let header = try? DraftHeader.parse(xml: xml) {
      return header
    }
    guard let text = try await fetch("txt") else { throw Missing() }
    return DraftHeader.parse(text: text)
  }
}
