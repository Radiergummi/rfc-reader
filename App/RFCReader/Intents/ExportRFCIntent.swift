import AppIntents
import RFCKit
import RFCReaderKit

#if os(macOS)
  import AppKit
#endif

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
    // A format made of the document loads it as every intent loads one, so a
    // failure to load says so; the export then finds it where this left it. The
    // RFC Editor's own files are not the document, and are not parsed for it.
    if format.source == .rendered {
      _ = try await IntentDocuments.load(id)
    }
    let data: Data
    do {
      data = try await DocumentExport.data(
        for: id, as: format, paperSize: Self.paperSize, library: LibraryModel.shared)
    } catch is CancellationError {
      throw CancellationError()
    } catch let noGrammar as ExportFormat.NoGrammar {
      // Its words name the RFC already.
      throw noGrammar
    } catch let original as PublishedOriginalPage.NotExportable {
      // So do these: a scan or a pointer, which the menus never export either.
      throw original
    } catch {
      // A published file fetched offline says so as a document that did not load.
      let failure = LoadFailure(error: error)
      if [.offline, .cellularDenied].contains(failure.kind) {
        throw IntentFailure.notAvailableOffline(id)
      }
      throw IntentFailure.notExported(id, reason: failure.message)
    }
    let file = IntentFile(
      data: data, filename: format.fileName(for: id), type: format.contentType)
    return .result(value: file)
  }

  /// The paper a PDF is laid out for: Page Setup's on the Mac, as File > Export…
  /// and a script use, and the region's on iOS.
  private static var paperSize: CGSize {
    #if os(macOS)
      NSPrintInfo.shared.paperSize
    #else
      PrintLayout.paperSize(for: .current)
    #endif
  }
}

/// The formats Shortcuts offers, by the names the menus give them (`ExportFormat.name`).
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

  /// The other way, a switch over the export's own formats: a format added there
  /// is a compile error here until Shortcuts offers it too.
  init(_ format: ExportFormat) {
    self =
      switch format {
      case .pdf: .pdf
      case .epub: .epub
      case .html: .html
      case .markdown: .markdown
      case .text: .text
      case .xml: .xml
      case .abnf: .abnf
      }
  }

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
