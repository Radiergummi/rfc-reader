import Foundation
import RFCKit
import UniformTypeIdentifiers

/// A file the open RFC can be saved as (#376).
///
/// One list, so the Mac's format pop-up, iOS's Export menu, the save panel's file
/// type and the file's name cannot disagree about what a format is called or what
/// it ends in. A format is added as a case here, and every surface offers it.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
  case pdf

  /// Where the file comes from.
  public enum Source: Sendable {
    /// The RFC Editor's own file, byte for byte.
    case published
    /// Generated from the parsed document, as the reader renders it.
    case rendered
  }

  public var id: String { rawValue }

  /// What menus and the format pop-up call it.
  public var name: String {
    switch self {
    case .pdf: "PDF"
    }
  }

  public var source: Source {
    switch self {
    case .pdf: .rendered
    }
  }

  public var contentType: UTType {
    switch self {
    case .pdf: .pdf
    }
  }

  public var pathExtension: String {
    contentType.preferredFilenameExtension ?? rawValue
  }

  /// `rfc9110.pdf`: the name the RFC Editor gives its own files, so an export sits
  /// beside a download of the same document under the name one would expect.
  public func fileName(for id: DocumentID) -> String {
    "\(id.fileStem).\(pathExtension)"
  }

  /// `name` with this format's extension in place of the one it has: what the save
  /// panel's name field becomes when the format changes, keeping whatever the
  /// name was changed to.
  public func renaming(_ name: String) -> String {
    let stem = (name as NSString).deletingPathExtension
    return "\(stem.isEmpty ? name : stem).\(pathExtension)"
  }

  /// The format a stored choice names, or the first one when it names none: the
  /// Mac's pop-up remembers the last format by its raw value, and a value from a
  /// build with a format this one does not have must not leave it with nothing.
  public init(remembered rawValue: String?) {
    self = rawValue.flatMap(Self.init(rawValue:)) ?? Self.allCases[0]
  }
}
