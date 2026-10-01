#if canImport(UIKit)
  import RFCReaderKit
  import SwiftUI
  import UIKit

  /// The document's number over its title, in the navigation bar's middle once the
  /// header that shows them has scrolled away: the iOS counterpart of the Mac's
  /// `ReaderToolbar.DocumentTitleView`, moved by the same `ToolbarTitleState`.
  ///
  /// Its text rises out from under the bar's bottom edge and fades in as the
  /// heading passes under the bar, scrubbing with the scroll; see
  /// `ToolbarTitleReveal`. Its subtitle names the section being read; see
  /// `RunningHeading`.
  struct DocumentTitle: UIViewRepresentable {
    let title: String
    let subtitle: String
    let reader: ReaderState
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func makeUIView(context: Context) -> DocumentTitleView {
      let view = DocumentTitleView()
      // A callback rather than observation, as on the Mac: the title is coupled to
      // the scroll, and observation delivers each change a run-loop turn late.
      reader.updateToolbarTitle = { [weak view] in view?.update($0) }
      return view
    }

    func updateUIView(_ view: DocumentTitleView, context: Context) {
      view.isCompact = verticalSizeClass == .compact
      view.show(title, subtitle: subtitle)
    }

    /// All the width the bar offers its middle, so a running heading changing
    /// from one section to the next never resizes the item. A proposal of no width
    /// or of unlimited width, which asks how wide the item would like to be, gets
    /// the text's own width: the item has no use for more, and an infinite width
    /// would end up in its labels' frames.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DocumentTitleView, context: Context)
      -> CGSize?
    {
      let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
      return CGSize(width: offered ?? uiView.fittingWidth, height: uiView.lineHeights)
    }
  }

  final class DocumentTitleView: UIView {
    private let title = DocumentTitleView.label(.label)
    /// The subtitle's line, clipped to itself: a section's heading hands over to
    /// the next inside it, one rising out as the other rises in.
    private let subtitleLine = UIView()
    private let outgoing = DocumentTitleView.label(.secondaryLabel)
    private let incoming = DocumentTitleView.label(.secondaryLabel)
    /// Title over subtitle, which the reveal moves as one.
    private let content = UIView()

    private var state = ToolbarTitleState.hidden
    /// What the subtitle says wherever no section's heading does: over the title
    /// page and the abstract.
    private var documentTitle = ""

    /// One line of each, measured when the type changes: it is fixed, as the bar's
    /// own title is, but for the bar's size, and a line's height does not depend
    /// on what it says.
    private var titleHeight: CGFloat = 0
    private var subtitleHeight: CGFloat = 0

    /// The bar is compact in an iPhone's landscape, about 32 pt where the type set
    /// for the regular bar takes 37: the smaller type keeps both lines inside it.
    var isCompact = false {
      didSet {
        guard isCompact != oldValue else { return }
        applyFonts()
        setNeedsLayout()
      }
    }

    var lineHeights: CGFloat { titleHeight + subtitleHeight }

    /// The wider of the two lines, for a bar that proposes no width.
    var fittingWidth: CGFloat {
      max(title.intrinsicContentSize.width, incoming.intrinsicContentSize.width)
    }

    init() {
      super.init(frame: .zero)
      applyFonts()
      // Everything is placed by frame, not by constraints: it moves on every
      // scroll tick, and a frame set inside a view whose own size does not change
      // dirties nothing outside it.
      subtitleLine.clipsToBounds = true
      subtitleLine.addSubview(outgoing)
      subtitleLine.addSubview(incoming)
      content.addSubview(title)
      content.addSubview(subtitleLine)
      addSubview(content)
      // The text rises from under the bar's bottom edge, which is this view's own
      // in the bar's middle: what is below it is out of sight.
      clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the title is built in code")
    }

    func show(_ title: String, subtitle: String) {
      if self.title.text != title { self.title.text = title }
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

    override func layoutSubviews() {
      super.layoutSubviews()
      // The lines' frames depend on the width alone.
      let width = bounds.width
      title.frame = CGRect(x: 0, y: 0, width: width, height: titleHeight)
      subtitleLine.frame = CGRect(x: 0, y: titleHeight, width: width, height: subtitleHeight)
      placeContent()
      placeHandOver()
    }

    private func applyFonts() {
      title.font = .systemFont(ofSize: isCompact ? 15 : 17, weight: .semibold)
      let subtitleFont = UIFont.systemFont(ofSize: isCompact ? 11 : 13)
      outgoing.font = subtitleFont
      incoming.font = subtitleFont
      titleHeight = ceil(title.font.lineHeight)
      subtitleHeight = ceil(subtitleFont.lineHeight)
    }

    /// Each label only when its words change: a label assigned the same string
    /// redraws for nothing.
    private func applyText() {
      let outgoingText = state.runningHeading.outgoing ?? documentTitle
      let incomingText = state.runningHeading.incoming ?? documentTitle
      if outgoing.text != outgoingText { outgoing.text = outgoingText }
      if incoming.text != incomingText { incoming.text = incomingText }
    }

    /// The reveal: title and subtitle, moved and faded as one.
    private func placeContent() {
      let top = ToolbarTitleReveal.top(
        atProgress: state.reveal, inBar: bounds.height, height: lineHeights)
      content.frame = CGRect(x: 0, y: top, width: bounds.width, height: lineHeights)
      content.alpha = ToolbarTitleReveal.opacity(atProgress: state.reveal)
      // Hidden, not only transparent, while out of sight: VoiceOver reads a
      // transparent label all the same.
      content.isHidden = state.reveal == 0
    }

    /// The hand-over: the outgoing heading rises out of the subtitle's line as
    /// the incoming one rises in, each transparent while the line's edge cuts it.
    private func placeHandOver() {
      let handOver = state.runningHeading.progress
      let width = bounds.width
      let incomingTop = ToolbarTitleReveal.top(
        atProgress: handOver, inBar: subtitleHeight, height: subtitleHeight)
      incoming.frame = CGRect(x: 0, y: incomingTop, width: width, height: subtitleHeight)
      outgoing.frame = CGRect(
        x: 0, y: incomingTop - subtitleHeight, width: width, height: subtitleHeight)
      outgoing.alpha = ToolbarTitleReveal.opacity(atProgress: 1 - handOver)
      incoming.alpha = ToolbarTitleReveal.opacity(atProgress: handOver)
      outgoing.isHidden = handOver == 1
      incoming.isHidden = handOver == 0
    }

    private static func label(_ color: UIColor) -> UILabel {
      let label = UILabel()
      label.textColor = color
      label.textAlignment = .center
      label.lineBreakMode = .byTruncatingTail
      return label
    }
  }
#endif
