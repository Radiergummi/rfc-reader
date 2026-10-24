import RFCKit
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// A note's editor (#523): a TextKit 2 text view, with lists as `NSTextList` paragraphs,
// over the note's body projected into attributed text (`NoteText`). What it saves is
// Markdown, so nothing stored depends on this editor. A popover on the Mac, a sheet on
// iOS; either way what the coordinator hosts reads nothing from the environment: the
// model carries everything it does as closures.

/// One note being edited: what it is on, its text view, and what saving, deleting and
/// following a link do.
@MainActor @Observable
final class NoteEditorModel {
  /// The text it opened with.
  @ObservationIgnored let initialText: NSAttributedString
  /// The Markdown it opened with.
  @ObservationIgnored let initialBody: String
  @ObservationIgnored let font: PlatformFont

  /// The link field ⌘K opens, and what is typed in it.
  var showsLinkField = false
  var linkText = ""
  /// Whether the field's text names nothing a link can go to.
  var linkIsInvalid = false

  @ObservationIgnored weak var textView: NoteTextView?
  @ObservationIgnored private let save: (String) -> Void
  @ObservationIgnored private let deleteNote: () -> Void
  @ObservationIgnored let openLink: (URL) -> Void
  /// Shows the note in the Annotations tab, on the Mac.
  @ObservationIgnored let showInAnnotations: (() -> Void)?
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  @ObservationIgnored private var isClosed = false
  /// What it saved last, which is what it holds once it has closed.
  @ObservationIgnored private(set) var saved: String?

  /// How long typing waits before it is saved.
  private static let saveDelay: Duration = .seconds(1)

  init(
    body: String, font: PlatformFont,
    save: @escaping (String) -> Void, delete: @escaping () -> Void,
    openLink: @escaping (URL) -> Void, showInAnnotations: (() -> Void)?
  ) {
    self.font = font
    let text = NSMutableAttributedString(
      attributedString: NoteText.attributed(NoteBody(markdown: body), font: font))
    text.addAttribute(
      .foregroundColor, value: RFCColors.label, range: NSRange(location: 0, length: text.length))
    initialText = text
    initialBody = body
    self.save = save
    self.deleteNote = delete
    self.openLink = openLink
    self.showInAnnotations = showInAnnotations
  }

  /// The text changed: saved once typing pauses.
  func textChanged() {
    pendingSave?.cancel()
    pendingSave = Task { [weak self] in
      guard await Debounce.outlasted(Self.saveDelay) else { return }
      self?.saveNow(closing: false)
    }
  }

  /// Saves what is typed. Emptied, it is deleted only as the editor closes: an
  /// empty pause mid-edit, as between a cut and a paste, would make it again later,
  /// as a new note.
  private func saveNow(closing: Bool) {
    guard !isClosed, let storage = textView?.noteStorage else { return }
    let body = NoteText.body(of: storage)
    guard closing || !body.isEmpty else { return }
    let markdown = body.markdown
    saved = markdown
    save(markdown)
  }

  /// The editor closes: what is typed is saved, and a note left empty is deleted.
  func close() {
    pendingSave?.cancel()
    saveNow(closing: true)
    isClosed = true
  }

  func delete() {
    pendingSave?.cancel()
    isClosed = true
    deleteNote()
  }

  // MARK: - Formatting

  func toggle(_ style: NoteBody.Style) {
    guard let textView, let storage = textView.noteStorage else { return }
    let range = textView.noteSelection
    guard range.length > 0 else {
      textView.typingAttributes = NoteText.toggling(
        style, in: textView.typingAttributes, font: font)
      return
    }
    textView.editAttributes(in: range) {
      NoteText.toggle(style, in: storage, range: range, font: font)
    }
    textChanged()
  }

  func toggleList(ordered: Bool) {
    guard let textView, let storage = textView.noteStorage else { return }
    let range = textView.noteSelection
    let paragraph = (storage.string as NSString).paragraphRange(for: range)
    guard paragraph.length > 0 else {
      // An empty last paragraph has no character to hold the list: what is typed
      // next does.
      textView.typingAttributes[.paragraphStyle] = NoteText.toggledTypingStyle(
        ordered: ordered,
        current: textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle, font: font)
      return
    }
    textView.editAttributes(in: range) {
      NoteText.toggleList(ordered: ordered, in: storage, range: range, font: font)
    }
    textView.carryParagraphStyleIntoTyping()
    textChanged()
  }

  func indent(by levels: Int) {
    guard let textView, let storage = textView.noteStorage else { return }
    let range = textView.noteSelection
    textView.editAttributes(in: range) {
      NoteText.indent(by: levels, in: storage, range: range, font: font)
    }
    textView.carryParagraphStyleIntoTyping()
    textChanged()
  }

  // MARK: - Links

  /// ⌘K: the link field, with the selection's link in it if it has one.
  func beginLink() {
    guard let textView, let storage = textView.noteStorage else { return }
    let range = NoteText.linkRange(textView.noteSelection, in: storage)
    let existing =
      range.length > 0 && range.location < storage.length
      ? storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL : nil
    linkText = existing?.absoluteString ?? ""
    linkIsInvalid = false
    showsLinkField = true
  }

  /// Puts the link typed over the selection, or inserts it as its own text where
  /// nothing is selected; an empty field takes the link off the selection.
  func applyLink() {
    guard let textView, let storage = textView.noteStorage else { return }
    let range = NoteText.linkRange(textView.noteSelection, in: storage)
    let typed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    if typed.isEmpty {
      if range.length > 0 {
        textView.editAttributes(in: range) { storage.removeAttribute(.link, range: range) }
        textChanged()
      }
      endLink()
      return
    }
    guard let url = NoteLink.url(from: typed) else {
      linkIsInvalid = true
      return
    }
    if range.length > 0 {
      textView.editAttributes(in: range) { storage.addAttribute(.link, value: url, range: range) }
    } else {
      var attributes = textView.typingAttributes
      attributes[.link] = url
      textView.insertNoteText(NSAttributedString(string: typed, attributes: attributes))
      // What is typed after it is not part of it.
      textView.typingAttributes[.link] = nil
    }
    textChanged()
    endLink()
  }

  func endLink() {
    showsLinkField = false
    linkIsInvalid = false
    textView?.focus()
  }
}

/// The editor: a formatting bar, the text, the link field when ⌘K opens it, and Delete.
struct NoteEditor: View {
  let model: NoteEditorModel

  /// The popover's width on the Mac.
  static let width: CGFloat = 380

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      formattingBar
      NoteTextEditor(model: model)
        .frame(minHeight: 140, idealHeight: 200, maxHeight: .infinity)
      if model.showsLinkField { linkField }
      HStack {
        Button("Delete Note", systemImage: "trash", role: .destructive) { model.delete() }
          .buttonStyle(.borderless)
        Spacer()
        if let show = model.showInAnnotations {
          Button("Show in Annotations", action: show)
            .buttonStyle(.borderless)
        }
      }
      .font(.callout)
    }
    .padding(12)
    .onDisappear { model.close() }
  }

  private var formattingBar: some View {
    HStack(spacing: 2) {
      button("Bold", systemImage: "bold") { model.toggle(.strong) }
      button("Italic", systemImage: "italic") { model.toggle(.emphasis) }
      button("Strikethrough", systemImage: "strikethrough") { model.toggle(.strikethrough) }
      button("Code", systemImage: "chevron.left.forwardslash.chevron.right") {
        model.toggle(.code)
      }
      Divider().frame(height: 16)
      button("Bulleted List", systemImage: "list.bullet") { model.toggleList(ordered: false) }
      button("Numbered List", systemImage: "list.number") { model.toggleList(ordered: true) }
      button("Decrease Indent", systemImage: "decrease.indent") { model.indent(by: -1) }
      button("Increase Indent", systemImage: "increase.indent") { model.indent(by: 1) }
      Divider().frame(height: 16)
      button("Link", systemImage: "link") { model.beginLink() }
    }
    .buttonStyle(.borderless)
  }

  private func button(
    _ title: LocalizedStringResource, systemImage: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .frame(width: 26, height: 22)
        .contentShape(.rect)
    }
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }

  private var linkField: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        TextField("URL or RFC, as RFC 9110 Section 4.2", text: $model.linkText)
          .textFieldStyle(.roundedBorder)
          .onSubmit { model.applyLink() }
          .onKeyPress(.escape) {
            model.endLink()
            return .handled
          }
        Button("Done") { model.applyLink() }
      }
      if model.linkIsInvalid {
        Text("That is neither an address nor an RFC.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - The text view

#if canImport(UIKit)
  /// The note's text view on iOS: TextKit 2, ⌘K for a link, ⌘B and ⌘I, and a paste
  /// reduced to what a note keeps.
  final class NoteTextView: UITextView {
    weak var model: NoteEditorModel?

    var noteStorage: NSTextStorage? { textStorage }
    var noteSelection: NSRange { selectedRange }

    /// The change, over the paragraphs `range` touches, which Undo takes back: a
    /// text view's storage changed directly registers nothing.
    func editAttributes(in range: NSRange, _ change: () -> Void) {
      let paragraphs = (textStorage.string as NSString).paragraphRange(for: range)
      let before = textStorage.attributedSubstring(from: paragraphs)
      textStorage.beginEditing()
      change()
      textStorage.endEditing()
      registerUndo(
        of: NSRange(location: paragraphs.location, length: paragraphs.length), was: before)
    }

    func insertNoteText(_ text: NSAttributedString) {
      let range = selectedRange
      let before = textStorage.attributedSubstring(from: range)
      textStorage.replaceCharacters(in: range, with: text)
      selectedRange = NSRange(location: range.location + text.length, length: 0)
      registerUndo(of: NSRange(location: range.location, length: text.length), was: before)
    }

    /// Undo puts `before` back over `range`, and registers putting it back again.
    private func registerUndo(of range: NSRange, was before: NSAttributedString) {
      undoManager?.registerUndo(withTarget: self) { textView in
        let now = textView.textStorage.attributedSubstring(from: range)
        textView.textStorage.replaceCharacters(in: range, with: before)
        textView.registerUndo(
          of: NSRange(location: range.location, length: before.length), was: now)
        textView.delegate?.textViewDidChange?(textView)
      }
    }

    /// An empty paragraph has no character to hold a list's style: what is typed
    /// next takes it.
    func carryParagraphStyleIntoTyping() {
      guard textStorage.length > 0 else { return }
      let location = min(selectedRange.location, textStorage.length - 1)
      if let style = textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil) {
        typingAttributes[.paragraphStyle] = style
      }
    }

    func focus() {
      becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
      let link = UIKeyCommand(
        title: String(localized: "Link"), action: #selector(linkCommand), input: "k",
        modifierFlags: .command)
      // Over Go to RFC, which ⌘K is elsewhere: in a note it is the link.
      link.wantsPriorityOverSystemBehavior = true
      return [link] + (super.keyCommands ?? [])
    }

    @objc private func linkCommand() {
      model?.beginLink()
    }

    /// The rich text a paste reduces to the note's scope, as the Mac's takes RTF,
    /// RTFD and HTML.
    private static let richTypes: [(String, NSAttributedString.DocumentType)] = [
      ("public.rtf", .rtf), ("com.apple.flat-rtfd", .rtfd), ("public.html", .html),
    ]

    override func paste(_ sender: Any?) {
      let board = UIPasteboard.general
      guard let font = model?.font else { return super.paste(sender) }
      if let string = board.string, let url = NoteLink.pasted(string) {
        var attributes = typingAttributes
        attributes[.link] = url
        insertNoteText(NSAttributedString(string: string, attributes: attributes))
      } else if let (data, type) = Self.richTypes.lazy.compactMap({ name, type in
        board.data(forPasteboardType: name).map { ($0, type) }
      }).first,
        let rich = try? NSAttributedString(
          data: data, options: [.documentType: type], documentAttributes: nil)
      {
        let reduced = NSMutableAttributedString(
          attributedString: NoteText.reduced(rich, font: font))
        reduced.addAttribute(
          .foregroundColor, value: RFCColors.label,
          range: NSRange(location: 0, length: reduced.length))
        insertNoteText(reduced)
      } else {
        return super.paste(sender)
      }
      delegate?.textViewDidChange?(self)
    }
  }

  struct NoteTextEditor: UIViewRepresentable {
    let model: NoteEditorModel

    func makeUIView(context: Context) -> NoteTextView {
      let textView = NoteTextView(usingTextLayoutManager: true)
      textView.model = model
      textView.allowsEditingTextAttributes = true
      textView.adjustsFontForContentSizeCategory = true
      textView.backgroundColor = .clear
      textView.attributedText = model.initialText
      textView.typingAttributes = [.font: model.font, .foregroundColor: RFCColors.label]
      textView.delegate = context.coordinator
      model.textView = textView
      Task { @MainActor in textView.becomeFirstResponder() }
      return textView
    }

    func updateUIView(_ textView: NoteTextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, UITextViewDelegate {
      let model: NoteEditorModel

      init(model: NoteEditorModel) {
        self.model = model
      }

      func textViewDidChange(_ textView: UITextView) {
        model.textChanged()
      }

      func textView(
        _ textView: UITextView, primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
      ) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return UIAction { [model] _ in model.openLink(url) }
      }
    }
  }
#else
  /// The note's text view on the Mac: TextKit 2, its own find bar, ⌘K for a link, ⌘B
  /// and ⌘I, and a paste reduced to what a note keeps.
  final class NoteTextView: NSTextView {
    weak var model: NoteEditorModel?

    var noteStorage: NSTextStorage? { textStorage }
    var noteSelection: NSRange { selectedRange() }

    /// Through the text view's own change, over the paragraphs `range` touches, as
    /// on iOS, so Undo takes back a list or an indent made with only the caret in it.
    func editAttributes(in range: NSRange, _ change: () -> Void) {
      let paragraphs = (string as NSString).paragraphRange(for: range)
      guard shouldChangeText(in: paragraphs, replacementString: nil) else { return }
      textStorage?.beginEditing()
      change()
      textStorage?.endEditing()
      didChangeText()
    }

    func insertNoteText(_ text: NSAttributedString) {
      insertText(text, replacementRange: selectedRange())
    }

    /// An empty paragraph has no character to hold a list's style: what is typed
    /// next takes it.
    func carryParagraphStyleIntoTyping() {
      guard let storage = textStorage, storage.length > 0 else { return }
      let location = min(selectedRange().location, storage.length - 1)
      if let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) {
        typingAttributes[.paragraphStyle] = style
      }
    }

    func focus() {
      window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard window != nil else { return }
      Task { @MainActor [weak self] in self?.focus() }
    }

    /// ⌘K is the link field here, wherever else it is something else; ⌘B and ⌘I
    /// bold and italic, which a popover's text has no Format menu for.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard window?.firstResponder === self,
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
        let key = event.charactersIgnoringModifiers?.lowercased()
      else { return super.performKeyEquivalent(with: event) }
      switch key {
      case "k": model?.beginLink()
      case "b": model?.toggle(.strong)
      case "i": model?.toggle(.emphasis)
      default: return super.performKeyEquivalent(with: event)
      }
      return true
    }

    override func paste(_ sender: Any?) {
      let board = NSPasteboard.general
      guard let font = model?.font else { return super.paste(sender) }
      if let string = board.string(forType: .string), let url = NoteLink.pasted(string) {
        var attributes = typingAttributes
        attributes[.link] = url
        insertNoteText(NSAttributedString(string: string, attributes: attributes))
      } else if board.availableType(from: [.rtf, .rtfd, .html]) != nil,
        let rich = board.readObjects(forClasses: [NSAttributedString.self])?.first
          as? NSAttributedString
      {
        let reduced = NSMutableAttributedString(
          attributedString: NoteText.reduced(rich, font: font))
        reduced.addAttribute(
          .foregroundColor, value: RFCColors.label,
          range: NSRange(location: 0, length: reduced.length))
        insertNoteText(reduced)
      } else {
        super.paste(sender)
      }
    }
  }

  struct NoteTextEditor: NSViewRepresentable {
    let model: NoteEditorModel

    func makeNSView(context: Context) -> NSScrollView {
      let textView = NoteTextView(usingTextLayoutManager: true)
      textView.model = model
      textView.isRichText = true
      textView.allowsUndo = true
      textView.importsGraphics = false
      textView.usesFontPanel = false
      textView.usesFindBar = true
      textView.isIncrementalSearchingEnabled = true
      textView.drawsBackground = false
      // Sized as a scroll view's document view has to be: as wide as the popover's
      // text, growing down with what is typed.
      let width = NoteEditor.width - 24
      textView.frame = CGRect(x: 0, y: 0, width: width, height: 0)
      textView.minSize = .zero
      textView.maxSize = CGSize(
        width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.autoresizingMask = [.width]
      textView.textContainer?.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
      textView.textContainer?.widthTracksTextView = true
      textView.textStorage?.setAttributedString(model.initialText)
      textView.typingAttributes = [.font: model.font, .foregroundColor: RFCColors.label]
      textView.delegate = context.coordinator
      model.textView = textView

      let scroll = NSScrollView()
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      scroll.documentView = textView
      // The find bar's place: Edit ▸ Find searches the note while it has the focus.
      scroll.isFindBarVisible = false
      return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    /// Detached from its container, as every TextKit 2 text view here is, or what
    /// AppKit keeps of it holds its text.
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
      (scroll.documentView as? NSTextView)?.textContainer?.textView = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextViewDelegate {
      let model: NoteEditorModel

      init(model: NoteEditorModel) {
        self.model = model
      }

      func textDidChange(_ notification: Notification) {
        model.textChanged()
      }

      func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url else { return false }
        model.openLink(url)
        return true
      }
    }
  }
#endif
