#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit

  /// The Format pop-up File > Export…'s save panel carries as its accessory, as
  /// Preview's Export does (#376).
  ///
  /// It keeps the panel's file type and the name's extension in step with the
  /// format, keeping whatever the name was changed to, and remembers the last format
  /// chosen for the next export.
  final class ExportFormatChooser: NSObject {
    static let rememberedKey = "exportFormat"

    let view: NSView
    private(set) var format: ExportFormat
    private let panel: NSSavePanel
    private let popUp = NSPopUpButton()

    init(panel: NSSavePanel, document: DocumentID) {
      self.panel = panel
      format = ExportFormat(remembered: UserDefaults.standard.string(forKey: Self.rememberedKey))
      popUp.addItems(withTitles: ExportFormat.allCases.map(\.name))
      popUp.selectItem(at: ExportFormat.allCases.firstIndex(of: format) ?? 0)
      let label = NSTextField(labelWithString: "Format:")
      let row = NSStackView(views: [label, popUp])
      row.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
      // The panel sizes its accessory by the view's frame, which a view made in
      // code starts without.
      row.frame.size = row.fittingSize
      view = row
      super.init()
      popUp.target = self
      popUp.action = #selector(choose)
      panel.allowedContentTypes = [format.contentType]
      panel.nameFieldStringValue = format.fileName(for: document)
    }

    @objc private func choose() {
      format = ExportFormat.allCases[popUp.indexOfSelectedItem]
      UserDefaults.standard.set(format.rawValue, forKey: Self.rememberedKey)
      panel.allowedContentTypes = [format.contentType]
      panel.nameFieldStringValue = format.renaming(panel.nameFieldStringValue)
    }
  }
#endif
