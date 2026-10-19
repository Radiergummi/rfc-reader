import CoreGraphics
import Foundation
import RFCKit
import RFCReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// The one place an export format becomes a file's contents (#376): the Mac's save
/// panel and iOS's Save to Files both ask here, so they save the same file. A
/// format #377 adds is a case here, and a case in `ExportFormat`.
enum DocumentExport {
  /// - Parameter paperSize: the page a rendered, paged format is laid out for.
  static func data(
    for id: DocumentID, as format: ExportFormat, paperSize: CGSize, library: LibraryModel
  ) async throws -> Data {
    switch format {
    case .pdf: try await DocumentPDF.export(id, paperSize: paperSize, library: library)
    case .abnf: try await grammar(of: id, library: library)
    case .markdown: try await annotations(of: id, library: library)
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

  /// The document's collected grammar (#185), offered only for a document that has
  /// one (`ReaderState.exportFormats`).
  private static func grammar(of id: DocumentID, library: LibraryModel) async throws -> Data {
    let document = try await library.document(for: id)
    guard let text = GrammarExport.text(for: document) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return Data(text.utf8)
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
