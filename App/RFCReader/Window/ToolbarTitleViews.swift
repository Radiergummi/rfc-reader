#if os(macOS)
  import AppKit
  import RFCReaderKit

  /// A title over a line of detail, as a window's own titlebar draws its title over
  /// its subtitle: the list's title.
  final class TitleStack: NSStackView {
    private let title = TitleStack.titleLabel()
    private let subtitle = TitleStack.subtitleLabel()

    /// What the longer of the two lines needs. Measured when the strings change,
    /// which is the only time it can: the list's title is capped once per frame of
    /// a divider drag, and reads this rather than measuring again.
    private(set) var textWidth: CGFloat = 0

    init() {
      super.init(frame: .zero)
      orientation = .vertical
      alignment = .leading
      spacing = 0
      addArrangedSubview(title)
      addArrangedSubview(subtitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      self.title.stringValue = title
      self.subtitle.stringValue = subtitle
      self.subtitle.isHidden = subtitle.isEmpty
      textWidth = max(
        self.title.intrinsicContentSize.width,
        subtitle.isEmpty ? 0 : self.subtitle.intrinsicContentSize.width
      )
    }

    /// The two lines' type, shared with the reader's title — which lays its lines
    /// out itself — so the toolbar's two titles cannot drift apart in type.
    static func titleLabel() -> NSTextField {
      label(.systemFont(ofSize: 13, weight: .semibold), .labelColor)
    }

    static func subtitleLabel() -> NSTextField {
      label(.systemFont(ofSize: 11), .secondaryLabelColor)
    }

    private static func label(_ font: NSFont, _ color: NSColor) -> NSTextField {
      let field = NSTextField(labelWithString: "")
      field.font = font
      field.textColor = color
      field.lineBreakMode = .byTruncatingTail
      field.cell?.usesSingleLineMode = true
      // Truncated rather than pushing its title wider than it was given.
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return field
    }
  }

  /// Title over subtitle, the shape a window's own titlebar draws — as a view we own,
  /// so that it takes the width of its text instead of every pixel that is going.
  final class TitleView: NSView {
    private let stack = TitleStack()

    /// The toolbar sizes a custom view from its constraints, and from nothing else:
    /// an intrinsic width alone left the title drawn on top of the navigation group,
    /// the same way the hosted SwiftUI items drew on top of each other.
    private var widthConstraint: NSLayoutConstraint!

    init() {
      super.init(frame: .zero)
      stack.translatesAutoresizingMaskIntoConstraints = false
      addSubview(stack)
      translatesAutoresizingMaskIntoConstraints = false
      widthConstraint = widthAnchor.constraint(equalToConstant: 1)
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(
          equalTo: leadingAnchor, constant: ToolbarTitleLayout.padding),
        stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        heightAnchor.constraint(equalToConstant: 32),
        widthConstraint,
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      stack.show(title, subtitle: subtitle)
      applyWidth()
    }

    /// The width of the column the title sits over. The labels truncate with an
    /// ellipsis inside whatever this leaves them.
    func limit(to column: CGFloat) {
      guard column != limit else { return }
      limit = column
      applyWidth()
    }

    private var limit: CGFloat = 0

    private func applyWidth() {
      let width = ToolbarTitleLayout.width(forText: stack.textWidth, inColumn: limit)
      // Assigning a constant dirties the titlebar's layout whether or not it moved.
      guard width != widthConstraint.constant else { return }
      widthConstraint.constant = width
    }
  }

  /// The document's number over its title, in the reader's own toolbar section once
  /// the header that shows them has scrolled away.
  ///
  /// It is the filler between Back/Forward and the document's actions — the item
  /// takes the place of the flexible space that stood there — and it shrinks to
  /// nothing rather than overflowing into the toolbar's chevron menu, drawing
  /// nothing at all below `ToolbarTitleLayout.isWorthDrawing`. Its text rises out
  /// from under the toolbar's bottom edge and fades in as the heading passes under
  /// the toolbar, scrubbing with the scroll; see `ToolbarTitleReveal`. Its subtitle
  /// names the section being read; see `RunningHeading`.
  final class DocumentTitleView: NSView {
    private let title = TitleStack.titleLabel()
    /// The subtitle's line, clipped to itself: a section's heading hands over to
    /// the next inside it, one rising out as the other rises in.
    private let subtitleLine = NSView()
    private let outgoing = TitleStack.subtitleLabel()
    private let incoming = TitleStack.subtitleLabel()
    /// Title over subtitle, which the reveal moves as one.
    private let content = NSView()
    /// What the text is clipped to: from the top of the item down to the toolbar's
    /// bottom edge, which is below the item's own — the toolbar gives the item 32
    /// pt in the middle of a taller bar. Clipped at the item's edge instead, the
    /// text appeared out of a line drawn across the middle of the toolbar.
    private let clip = NSView()

    private var state = ToolbarTitleState.hidden
    /// What the subtitle says wherever no section's heading does: over the title
    /// page and the abstract.
    private var documentTitle = ""
    /// The toolbar's bottom edge, in this view's coordinates: below zero.
    private var toolbarBottom: CGFloat = 0

    /// One line of each, measured once: the type is fixed, and a line's height
    /// does not depend on what it says.
    private let titleHeight: CGFloat
    private let subtitleHeight: CGFloat

    init() {
      titleHeight = TitleStack.titleLabel().fittingSize.height
      subtitleHeight = TitleStack.subtitleLabel().fittingSize.height
      super.init(frame: .zero)
      // Everything is placed by frame, not by constraints: it moves on every
      // scroll tick, and a frame set inside a view whose own size does not change
      // dirties nothing outside it.
      subtitleLine.wantsLayer = true
      subtitleLine.layer?.masksToBounds = true
      subtitleLine.addSubview(outgoing)
      subtitleLine.addSubview(incoming)
      content.addSubview(title)
      content.addSubview(subtitleLine)
      clip.wantsLayer = true
      clip.layer?.masksToBounds = true
      clip.addSubview(content)
      addSubview(clip)
      // The clip reaches below this view's bounds, so this view must not cut it
      // off at its own edge. Its size is the item's `minSize` and `maxSize`.
      clipsToBounds = false
      placeContent()
      placeHandOver()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      self.title.stringValue = title
      documentTitle = subtitle
      applyText()
    }

    /// Only what changed: while the title slides in the hand-over holds still,
    /// and while a heading hands over the title does, so a scroll tick moves one
    /// or the other rather than every view in the item.
    func update(_ state: ToolbarTitleState) {
      let previous = self.state
      self.state = state
      if state.runningHeading.outgoing != previous.runningHeading.outgoing
        || state.runningHeading.incoming != previous.runningHeading.incoming
      {
        applyText()
      }
      if state.reveal != previous.reveal {
        placeContent()
      }
      if state.runningHeading.progress != previous.runningHeading.progress {
        placeHandOver()
      }
    }

    override func layout() {
      super.layout()
      // Where the toolbar ends, which is where the window's content begins. Only
      // a layout pass can move it, so it is measured here rather than per tick.
      if let window {
        let edge = convert(NSPoint(x: 0, y: window.contentLayoutRect.maxY), from: nil).y
        toolbarBottom = min(0, edge)
      }
      clip.frame = CGRect(
        x: 0, y: toolbarBottom, width: bounds.width, height: bounds.height - toolbarBottom)
      // The lines' frames depend on the width alone.
      let width = lineWidth
      title.frame = CGRect(x: 0, y: subtitleHeight, width: width, height: titleHeight)
      subtitleLine.frame = CGRect(x: 0, y: 0, width: width, height: subtitleHeight)
      placeContent()
      placeHandOver()
    }

    private var lineWidth: CGFloat {
      max(0, bounds.width - ToolbarTitleLayout.padding * 2)
    }

    /// Each label only when its words change: a label assigned the same string
    /// redraws for nothing.
    private func applyText() {
      let outgoingText = state.runningHeading.outgoing ?? documentTitle
      let incomingText = state.runningHeading.incoming ?? documentTitle
      if outgoing.stringValue != outgoingText { outgoing.stringValue = outgoingText }
      if incoming.stringValue != incomingText { incoming.stringValue = incomingText }
    }

    /// The reveal: title and subtitle, moved and faded as one.
    private func placeContent() {
      // Not flipped, so up is a larger y. At 0 the text's top is at the
      // toolbar's bottom edge, just out of sight under it; at 1 it rests in the
      // middle of the item.
      let height = titleHeight + subtitleHeight
      let hidden = toolbarBottom - height
      let resting = (bounds.height - height) / 2
      let y = hidden + (resting - hidden) * state.reveal
      content.frame = CGRect(
        x: ToolbarTitleLayout.padding, y: y - toolbarBottom, width: lineWidth, height: height)
      // On the text, not on this view: the toolbar sets its items' own alpha
      // for their enabled state and overrides whatever is set here.
      content.alphaValue = ToolbarTitleReveal.opacity(atProgress: state.reveal)
      // Hidden, not only transparent, while out of sight or too narrow to say
      // anything: VoiceOver reads a transparent label all the same.
      content.isHidden =
        state.reveal == 0 || !ToolbarTitleLayout.isWorthDrawing(width: bounds.width)
    }

    /// The hand-over: the outgoing heading rises out of the subtitle's line as
    /// the incoming one rises in, each transparent while the line's edge cuts it.
    private func placeHandOver() {
      let handOver = state.runningHeading.progress
      let width = lineWidth
      outgoing.frame = CGRect(
        x: 0, y: handOver * subtitleHeight, width: width, height: subtitleHeight)
      incoming.frame = CGRect(
        x: 0, y: (handOver - 1) * subtitleHeight, width: width, height: subtitleHeight)
      outgoing.alphaValue = ToolbarTitleReveal.opacity(atProgress: 1 - handOver)
      incoming.alphaValue = ToolbarTitleReveal.opacity(atProgress: handOver)
      outgoing.isHidden = handOver == 1
      incoming.isHidden = handOver == 0
    }
  }
#endif
