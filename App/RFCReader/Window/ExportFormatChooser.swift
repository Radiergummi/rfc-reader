#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit

  /// The Format pop-up File > Export…'s save panel carries as its accessory, as
  /// Preview's Export does (#376).
  ///
  /// It keeps the panel's file type and the name's extension in step with the
  /// format, keeping whatever the name was changed to, and remembers the last format
  /// chosen for the next export. With a section on screen, a second pop-up chooses
  /// the whole document or that section (#386), for a format that narrows.
  final class ExportFormatChooser: NSObject {
    static let rememberedKey = "exportFormat"

    let view: NSView
    private(set) var format: ExportFormat
    private let panel: NSSavePanel
    private let popUp = NSPopUpButton()
    /// The formats this document can be saved as (#185).
    private let offered: [ExportFormat]
    private let document: DocumentID
    /// The anchor of the section on screen, which the scope pop-up offers.
    private let currentSection: String?
    private let scopePopUp = NSPopUpButton()
    private(set) var scope = ExportScope.wholeDocument

    /// The section to export: the one on screen, when it is chosen and the format
    /// takes a section; nil for the whole document.
    var section: String? {
      scope.section(currentSection, for: format)
    }
    /// The name the panel was last given for a format and scope, which a change of
    /// either replaces; a name typed over it is kept, with the extension changed.
    private var givenName = ""

    init(
      panel: NSSavePanel, document: DocumentID, offered: [ExportFormat], currentSection: String?
    ) {
      self.panel = panel
      self.offered = offered
      self.document = document
      self.currentSection = currentSection
      format = ExportFormat(
        remembered: UserDefaults.standard.string(forKey: Self.rememberedKey), offered: offered)
      popUp.addItems(withTitles: offered.map { $0.name() })
      popUp.selectItem(at: offered.firstIndex(of: format) ?? 0)
      let label = NSTextField(labelWithString: String(localized: "Format:"))
      var rows = [NSStackView(views: [label, popUp])]
      if currentSection != nil {
        scopePopUp.addItems(withTitles: ExportScope.allCases.map { $0.name() })
        let scopeLabel = NSTextField(labelWithString: String(localized: "Contents:"))
        rows.append(NSStackView(views: [scopeLabel, scopePopUp]))
      }
      let stack = NSStackView(views: rows)
      stack.orientation = .vertical
      stack.alignment = .trailing
      stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
      // The panel sizes its accessory by the view's frame, which a view made in
      // code starts without.
      stack.frame.size = stack.fittingSize
      view = stack
      super.init()
      popUp.target = self
      popUp.action = #selector(choose)
      scopePopUp.target = self
      scopePopUp.action = #selector(chooseScope)
      scopePopUp.isEnabled = format.narrows
      panel.allowedContentTypes = [format.contentType]
      giveName()
    }

    @objc private func choose() {
      format = offered[popUp.indexOfSelectedItem]
      UserDefaults.standard.set(format.rawValue, forKey: Self.rememberedKey)
      panel.allowedContentTypes = [format.contentType]
      scopePopUp.isEnabled = format.narrows
      if panel.nameFieldStringValue == givenName {
        giveName()
      } else {
        panel.nameFieldStringValue = format.renaming(panel.nameFieldStringValue)
      }
    }

    /// The name a new export in this format and scope is given, given.
    private func giveName() {
      givenName = format.fileName(for: document, section: section)
      panel.nameFieldStringValue = givenName
    }

    /// The whole document or the section: the name becomes the one this scope
    /// gives, as a new export would.
    @objc private func chooseScope() {
      scope = ExportScope.allCases[scopePopUp.indexOfSelectedItem]
      giveName()
    }
  }
#endif
