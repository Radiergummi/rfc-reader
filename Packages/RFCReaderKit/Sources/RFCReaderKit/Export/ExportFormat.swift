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
  /// An EPUB 3 book, one content document per top-level section (#408).
  case epub
  /// One self-contained page that reads like the reader (#377).
  case html
  case markdown
  /// The RFC Editor's `.txt`, pages and all.
  case text
  /// The RFC Editor's RFCXML; for a legacy RFC, which never was published as XML,
  /// the app's conversion of it, which the file says it is (`convertedXML(of:)`).
  case xml
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
  public func name(in locale: Locale = .interface) -> String {
    switch self {
    case .pdf: "PDF"
    case .epub: "EPUB"
    case .html: "HTML"
    case .markdown: "Markdown"
    case .text: String(kit: "Plain Text", locale: locale)
    case .xml: "XML"
    case .abnf: String(kit: "ABNF Grammar", locale: locale)
    }
  }

  public var source: Source {
    switch self {
    case .pdf, .epub, .html, .markdown, .abnf: .rendered
    case .text, .xml: .published
    }
  }

  public var contentType: UTType {
    switch self {
    case .pdf: .pdf
    case .epub: .epub
    case .html: .html
    // Gruber's own identifier, which macOS declares; the extension where it is not.
    case .markdown:
      UTType("net.daringfireball.markdown")
        ?? UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    case .text: .plainText
    case .xml: .xml
    // No system type declares ABNF: plain text by the `.abnf` extension, which a save
    // panel and a file exporter keep only for a type that is the extension's.
    case .abnf: UTType(filenameExtension: "abnf", conformingTo: .plainText) ?? .plainText
    }
  }

  public var pathExtension: String {
    switch self {
    case .pdf: contentType.preferredFilenameExtension ?? rawValue
    case .epub: "epub"
    case .html: "html"
    case .markdown: "md"
    case .text: "txt"
    case .xml: "xml"
    case .abnf: "abnf"
    }
  }

  /// The formats every document can be saved as.
  public static let everyDocument: [ExportFormat] = [
    .pdf, .epub, .html, .markdown, .text, .xml,
  ]

  /// The formats `document` can be saved as: `everyDocument`, and its grammar where
  /// it has one.
  public static func available(for document: RFCDocument, hints: ArtworkHints = .bundled)
    -> [ExportFormat]
  {
    let hasGrammar = DocumentGrammar.blocks(of: document, hints: hints).contains {
      ABNFPresentation.dialect(ofType: $0.content.type) == .rfc5234
        && ABNF.parse($0.content.text) != nil
    }
    return hasGrammar ? everyDocument + [.abnf] : everyDocument
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

extension ExportFormat {
  /// The file this format makes of `document` itself: the page, the Markdown or the
  /// grammar. Nil for PDF, which is laid out (`PDFExport`), for the EPUB, which is
  /// an archive (`data(of:)`), for the RFC Editor's own files, and for a grammar
  /// `document` does not have.
  public func text(of document: RFCDocument) -> String? {
    switch self {
    case .html: RFCHTMLSerializer().page(document)
    case .markdown: RFCMarkdownSerializer().serialize(document)
    case .abnf: GrammarExport.text(for: document)
    case .pdf, .epub, .text, .xml: nil
    }
  }

  /// The file this format makes of `document` itself: `text(of:)`'s, or the EPUB.
  /// Nil where `text(of:)` is, but for the EPUB. What every surface that saves a
  /// file asks, so they save the same one.
  public func data(of document: RFCDocument) -> Data? {
    if self == .epub { return RFCEPUBWriter().epub(document) }
    return text(of: document).map { Data($0.utf8) }
  }

  /// A legacy RFC as XML, which the RFC Editor never published it as: the document
  /// as the app holds it, through the serializer the corpus is converted with, with
  /// a comment that says what it is and a link to the text it came from.
  public static func convertedXML(of document: RFCDocument) -> String {
    let source = document.header.id.map { RFCEditorEndpoints.document($0, format: .text) }
    let serializer = RFCXMLSerializer(
      options: .init(
        generatorComment:
          "Converted by RFC Reader from the plain-text RFC, which was never published as XML. Structure recovered heuristically; the text itself is unchanged.",
        sourceURL: source))
    return serializer.serialize(document)
  }
}
