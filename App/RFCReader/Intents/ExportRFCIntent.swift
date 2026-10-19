import AppIntents
import RFCKit
import RFCReaderKit

/// "Export RFC 9110 as PDF" (#384): the file File > Export… writes, made by the
/// same `DocumentExport`, handed to the shortcut to save, share or pass on, without
/// opening a window.
struct ExportRFCIntent: AppIntent {
  static let title: LocalizedStringResource = "Export RFC"
  static let description = IntentDescription(
    "Saves an RFC as a file in a format, which a shortcut can save, share or pass on.")

  @Parameter(title: "RFC")
  var document: RFCEntity

  @Parameter(title: "Format", default: .pdf)
  var format: IntentExportFormat

  static var parameterSummary: some ParameterSummary {
    Summary("Export \(\.$document) as \(\.$format)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    let id = document.documentID
    let format = format.format
    // The index says which formats the document has, which decides what is fetched.
    guard await LibraryModel.shared.settledSearch() != nil else {
      throw IntentFailure.indexUnavailable
    }
    let data: Data
    do {
      data = try await DocumentExport.data(
        for: id, as: format, paperSize: PrintLayout.paperSize(for: .current),
        library: LibraryModel.shared)
    } catch let error as CocoaError where format == .abnf && error.code == .fileWriteUnknown {
      // What `DocumentExport` throws for a grammar the RFC does not have.
      throw IntentFailure.noGrammar(id)
    } catch {
      let failure = LoadFailure(error: error)
      if [.offline, .cellularDenied].contains(failure.kind) {
        throw IntentFailure.notAvailableOffline(id)
      }
      throw IntentFailure.notLoaded(id, reason: failure.message)
    }
    let file = IntentFile(
      data: data, filename: format.fileName(for: id), type: format.contentType)
    return .result(value: file)
  }
}

/// The formats Shortcuts offers, by the names the menus give them.
///
/// An enumeration of the app's own, and its names written out rather than read from
/// `ExportFormat.name(in:)`: the App Intents metadata step reads an `AppEnum`'s
/// cases and names at build time, from a literal, and from no enumeration of
/// another module. `format` maps each to the export's own.
enum IntentExportFormat: String, AppEnum {
  case pdf
  case epub
  case html
  case markdown
  case text
  case xml
  case abnf

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"

  static let caseDisplayRepresentations: [IntentExportFormat: DisplayRepresentation] = [
    .pdf: "PDF",
    .epub: "EPUB",
    .html: "HTML",
    .markdown: "Markdown",
    .text: "Plain Text",
    .xml: "XML",
    .abnf: "ABNF Grammar",
  ]

  var format: ExportFormat {
    switch self {
    case .pdf: .pdf
    case .epub: .epub
    case .html: .html
    case .markdown: .markdown
    case .text: .text
    case .xml: .xml
    case .abnf: .abnf
    }
  }
}
