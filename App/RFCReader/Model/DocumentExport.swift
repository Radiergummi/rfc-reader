import CoreGraphics
import Foundation
import RFCKit
import RFCReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// The one place an export format becomes a file's contents (#376): the Mac's save
/// panel and iOS's Save to Files both ask here, so they save the same file. What a
/// format makes of the document itself is `ExportFormat.text(of:)`'s; here is only
/// where the document and the published files come from.
enum DocumentExport {
  /// - Parameter paperSize: the page a rendered, paged format is laid out for.
  static func data(
    for id: DocumentID, as format: ExportFormat, paperSize: CGSize, library: LibraryModel
  ) async throws -> Data {
    switch format {
    case .pdf: try await DocumentPDF.export(id, paperSize: paperSize, library: library)
    case .text: try await library.publishedFile(for: id, format: .text)
    case .xml: try await xml(of: id, library: library)
    case .html, .markdown, .abnf: try await rendered(id, as: format, library: library)
    }
  }

  /// The page, the Markdown or the collected grammar (#185); the grammar is offered
  /// only for a document that has one (`ReaderState.exportFormats`).
  private static func rendered(_ id: DocumentID, as format: ExportFormat, library: LibraryModel)
    async throws -> Data
  {
    let document = try await library.document(for: id)
    guard let text = format.text(of: document) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return Data(text.utf8)
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
    return Data(ExportFormat.convertedXML(of: try await library.document(for: id)).utf8)
  }
}

#if !os(macOS)
  /// A finished export, for SwiftUI's `fileExporter`, which saves a `FileDocument`.
  /// Written only: nothing is ever opened as one.
  nonisolated struct ExportedFile: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { ExportFormat.allCases.map(\.contentType) }

    let data: Data
    let format: ExportFormat

    init(data: Data, format: ExportFormat) {
      self.data = data
      self.format = format
    }

    init(configuration: ReadConfiguration) throws {
      throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
      FileWrapper(regularFileWithContents: data)
    }
  }
#endif
