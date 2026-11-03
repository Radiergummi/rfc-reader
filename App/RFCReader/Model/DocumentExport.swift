import CoreGraphics
import Foundation
import RFCKit
import RFCReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// The one place an export format becomes a file's contents (#376): the Mac's save
/// panel and iOS's Save to Files both ask here, so they save the same file. What a
/// format makes of the document itself is `ExportFormat.data(of:)`'s; here is only
/// where the document and the published files come from.
enum DocumentExport {
  /// - Parameters:
  ///   - section: the anchor of the one section to export, with its subsections
  ///     (#386), for a format that `narrows`; nil for the whole document.
  ///   - paperSize: the page a rendered, paged format is laid out for.
  static func data(
    for id: DocumentID, as format: ExportFormat, section: String? = nil, paperSize: CGSize,
    library: LibraryModel
  ) async throws -> Data {
    try await checkExportable(id, library: library)
    let section = format.narrows ? section : nil
    return switch format {
    case .pdf:
      try await DocumentPDF.export(id, section: section, paperSize: paperSize, library: library)
    case .text: try await library.publishedFile(for: id, format: .text)
    case .xml: try await xml(of: id, library: library)
    case .annotations: try await annotations(of: id, library: library)
    case .epub, .html, .markdown, .abnf:
      try await rendered(id, as: format, section: section, library: library)
    }
  }

  /// The document's highlights and notes (#524), as the store has them now.
  private static func annotations(of id: DocumentID, library: LibraryModel) async throws -> Data {
    let document = try await library.document(for: id)
    let annotations = library.annotations
    let text = await markdown(of: document, id: id, annotations: annotations)
    return Data(text.utf8)
  }

  /// Off the main actor: placing the annotations reads the whole model text.
  @concurrent
  private static func markdown(
    of document: RFCDocument, id: DocumentID, annotations: AnnotationSnapshot
  ) async -> String {
    AnnotationExport.markdown(of: document, id: id, annotations: annotations, exported: .now)
  }

  /// Refuses what Print and Export do not offer (`ReaderState.offersPrintAndExport`),
  /// so that a script, a shortcut and a collection's export refuse it too: a scan,
  /// which has no text, and a pointer, whose text only says where the RFC is
  /// (`PublishedOriginalPage.NotExportable`). The text is read only for an RFC the
  /// index lists an original of beside it, as the export would read it anyway.
  private static func checkExportable(_ id: DocumentID, library: LibraryModel) async throws {
    let formats = library.metadata(id)?.formats
    let text =
      PublishedOriginalPage.exportReadsText(id, formats: formats)
      ? try await library.document(for: id) : nil
    try PublishedOriginalPage.checkExportable(
      id, formats: formats, text: text, pointerInPack: library.pointersInPack.contains(id))
  }

  /// The book, the page, the Markdown or the collected grammar (#185); the grammar is offered
  /// only for a document that has one (`ReaderState.exportFormats`).
  private static func rendered(
    _ id: DocumentID, as format: ExportFormat, section: String?, library: LibraryModel
  ) async throws -> Data {
    let part = try ExportedPart(of: try await library.document(for: id), section: section)
    guard let data = await serialized(part, as: format) else {
      // Only a grammar can be missing: every other rendered format is made of any
      // document.
      throw format == .abnf ? ExportFormat.NoGrammar(document: id) : CocoaError(.fileWriteUnknown)
    }
    return data
  }

  /// `format.data(of:)`, off the main actor: a large RFC's book is two passes over
  /// the whole document and a checksum over every byte of it.
  @concurrent
  private static func serialized(_ part: ExportedPart, as format: ExportFormat) async -> Data? {
    format.data(of: part)
  }

  /// The RFC Editor's XML where it published one, and the app's conversion of the
  /// text where it did not: a legacy RFC's index entry lists no XML, and one the
  /// index has not named yet is asked for, and converted when there is none.
  private static func xml(of id: DocumentID, library: LibraryModel) async throws -> Data {
    let formats = library.metadata(id)?.formats
    if !RFCEditorClient.textIsTheDocument(availableFormats: formats) {
      do {
        return try await library.publishedFile(for: id, format: .xml)
      } catch RFCEditorClient.ClientError.notFound {
        // Never published as XML: converted below.
      }
    }
    return await converted(try await library.document(for: id))
  }

  @concurrent
  private static func converted(_ document: RFCDocument) async -> Data {
    Data(ExportFormat.convertedXML(of: document).utf8)
  }
}

#if !os(macOS)
  /// A finished export, or a published format an Info pane row downloaded (#577), for
  /// SwiftUI's `fileExporter`, which saves a `FileDocument`. Written only: nothing is
  /// ever opened as one.
  nonisolated struct ExportedFile: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] {
      ExportFormat.allCases.map(\.contentType) + FileFormat.allCases.map(\.contentType)
    }

    let data: Data
    /// What Save to Files saves it as, which keeps the extension of this type only.
    let contentType: UTType
    /// What Save to Files names it, without the extension it adds.
    let fileStem: String

    init(data: Data, contentType: UTType, fileStem: String) {
      self.data = data
      self.contentType = contentType
      self.fileStem = fileStem
    }

    init(configuration: ReadConfiguration) throws {
      throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
      FileWrapper(regularFileWithContents: data)
    }
  }
#endif
