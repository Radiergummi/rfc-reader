#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit

  /// The Format pop-up File > Export…'s save panel carries as its accessory, as
  /// Preview's Export does (#376).
  ///
  /// It keeps the panel's file type and the name's extension in step with the
  /// format, keeping whatever the name was changed to, and remembers the last format
  /// chosen for the next export (`ExportFormat.isRemembered`). Whether the whole
  /// document or the section on screen is saved (#386) is chosen before the panel
  /// opens, by File > Export… or Export Current Section…: the panel runs in a
  /// process of its own in the sandbox, and a name given to it once it is open
  /// never reaches its field, so a scope chosen in it could not name the file.
  final class ExportFormatChooser: NSObject {
    static let rememberedKey = "exportFormat"

    let view: NSView
    private(set) var format: ExportFormat
    private let panel: NSSavePanel
    private let popUp = NSPopUpButton()
    /// The formats this document can be saved as (#185), only those that take a
    /// section when one is saved.
    private let offered: [ExportFormat]
    private let document: DocumentID
    private let section: String?

    /// - Parameter section: the anchor of the section to save, which names the
    ///   file; nil for the whole document.
    init(
      panel: NSSavePanel, document: DocumentID, offered: [ExportFormat], section: String?
    ) {
      self.panel = panel
      self.offered = offered
      self.document = document
      self.section = section
      format = ExportFormat(
        remembered: UserDefaults.standard.string(forKey: Self.rememberedKey), offered: offered)
      popUp.addItems(withTitles: offered.map { $0.name() })
      popUp.selectItem(at: offered.firstIndex(of: format) ?? 0)
      let label = NSTextField(labelWithString: String(localized: "Format:"))
      let stack = NSStackView(views: [label, popUp])
      stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
      // The panel sizes its accessory by the view's frame, which a view made in
      // code starts without.
      stack.frame.size = stack.fittingSize
      view = stack
      super.init()
      popUp.target = self
      popUp.action = #selector(choose)
      panel.allowedContentTypes = [format.contentType]
      panel.nameFieldStringValue = format.fileName(for: document, section: section)
    }

    @objc private func choose() {
      let previous = format
      format = offered[popUp.indexOfSelectedItem]
      if format.isRemembered {
        UserDefaults.standard.set(format.rawValue, forKey: Self.rememberedKey)
      }
      panel.allowedContentTypes = [format.contentType]
      panel.nameFieldStringValue = format.renaming(
        panel.nameFieldStringValue, from: previous, for: document, section: section)
    }
  }
#endif
