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
  /// The document's grammar collected into one file (#185), for a document with one.
  case abnf

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
    case .abnf: "ABNF Grammar"
    }
  }

  public var source: Source {
    switch self {
    case .pdf, .abnf: .rendered
    }
  }

  public var contentType: UTType {
    switch self {
    case .pdf: .pdf
    // No system type declares ABNF: plain text, saved as `.abnf`.
    case .abnf: .plainText
    }
  }

  public var pathExtension: String {
    switch self {
    case .pdf: contentType.preferredFilenameExtension ?? rawValue
    case .abnf: "abnf"
    }
  }

  /// The formats `document` can be saved as: PDF always, and its grammar where it
  /// has one.
  public static func available(for document: RFCDocument, hints: ArtworkHints = .bundled)
    -> [ExportFormat]
  {
    GrammarExport.text(for: document, hints: hints) == nil ? [.pdf] : [.pdf, .abnf]
  }

  /// `RFC-10042.pdf`, `BCP-14.pdf`: the document as it is cited, which reads as a
  /// name in Finder, rather than the RFC Editor's `rfc10042`.
  public func fileName(for id: DocumentID) -> String {
    "\(Self.fileStem(for: id)).\(pathExtension)"
  }

  /// `RFC-10042`: a file name without its extension, which iOS's Save to Files adds
  /// for the format itself.
  public static func fileStem(for id: DocumentID) -> String {
    "\(id.series.rawValue)-\(id.number)"
  }

  /// `name` with this format's extension in place of the one it has: what the save
  /// panel's name field becomes when the format changes, keeping whatever the
  /// name was changed to. Only a suffix that names a file type is an extension:
  /// the `.2` of `RFC-10042 v1.2` is part of the name, and stays.
  public func renaming(_ name: String) -> String {
    let suffix = (name as NSString).pathExtension
    let isFileType =
      Self.allCases.contains { $0.pathExtension == suffix.lowercased() }
      || (UTType(filenameExtension: suffix).map { !$0.isDynamic } ?? false)
    let stem = isFileType ? (name as NSString).deletingPathExtension : name
    return "\(stem.isEmpty ? name : stem).\(pathExtension)"
  }

  /// The Finder tags an exported file is offered with (Mac): `RFC`, the working
  /// group, and the status, as the reader's lists show it. Nothing the index does
  /// not know.
  public static func tagNames(for metadata: RFCMetadata?) -> [String] {
    ["RFC"] + classification(metadata)
  }

  /// The working group and the status: what an exported file's tags and its PDF
  /// keywords both say it is filed under.
  static func classification(_ metadata: RFCMetadata?) -> [String] {
    let status = metadata?.currentStatus
    return [metadata?.namedWorkingGroup, status == .unknown ? nil : status?.displayName]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
  }

  /// The format a stored choice names, or the first one when it names none: the
  /// Mac's pop-up remembers the last format by its raw value, and a value from a
  /// build with a format this one does not have must not leave it with nothing.
  public init(remembered rawValue: String?) {
    self.init(remembered: rawValue, offered: Self.allCases)
  }

  /// The format a stored choice names, among those `offered` for one document, or
  /// the first offered: a grammar remembered from one document is not one another
  /// can be saved as.
  public init(remembered rawValue: String?, offered: [ExportFormat]) {
    let remembered = rawValue.flatMap(Self.init(rawValue:))
    self = remembered.flatMap { offered.contains($0) ? $0 : nil } ?? offered.first ?? .pdf
  }
}
