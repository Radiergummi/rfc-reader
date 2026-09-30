import RFCReaderKit

#if canImport(UIKit)
  import UIKit

  /// A rendered block's Figure | Source button, told apart from the text view's
  /// other subviews by its class.
  final class FigureButton: UIButton {}
#else
  import AppKit

  /// A rendered block's Figure | Source button, told apart from the text view's
  /// other subviews by its class: over it the pointer is the arrow.
  final class FigureButton: NSButton {}
#endif

/// The buttons that switch a rendered block between its figure and its source:
/// native icon buttons laid over the text view in the strip the builder reserves
/// above the block's first line, where no text is. Subviews of the text view, so
/// they scroll with it; placed again only when the text moves under them. A print
/// or an export draws fragments alone, so never shows one.
///
/// On iOS every block whose first line is on screen shows its button; on macOS only
/// the one the pointer is over, so a page of diagrams is not covered in buttons.
final class FigureControls {
  /// The installed document's blocks that have a button.
  var blocks: [FigureControl.Block] = []
  /// The block the pointer is over, on macOS.
  var hovered: Int?
  /// Showing, by the ordinal of the block each belongs to.
  private var placed: [Int: FigureButton] = [:]
  private var spare: [FigureButton] = []

  func frame(of ordinal: Int?) -> CGRect? {
    ordinal.flatMap { placed[$0]?.frame }
  }

  /// Shows a button at each frame, in the text view's coordinates, and hides the
  /// rest.
  func show(
    _ wanted: [(control: FigureControl.Control, frame: CGRect)], over view: PlatformTextView,
    target: AnyObject, action: Selector
  ) {
    let ordinals = Set(wanted.map(\.control.ordinal))
    for (ordinal, button) in placed where !ordinals.contains(ordinal) {
      placed[ordinal] = nil
      button.isHidden = true
      spare.append(button)
    }
    for (control, frame) in wanted {
      let button =
        placed[control.ordinal] ?? spare.popLast() ?? make(target: target, action: action)
      if button.superview !== view { view.addSubview(button) }
      button.isHidden = false
      button.frame = frame
      button.tag = control.ordinal
      offer(from: control.shown, on: button)
      placed[control.ordinal] = button
    }
  }

  /// The symbol and the words of the presentation `shown` switches to.
  private func offer(from shown: FigureControl.Segment, on button: FigureButton) {
    let title = FigureControl.title(offeredFrom: shown)
    let symbol = FigureControl.symbol(offeredFrom: shown)
    #if canImport(UIKit)
      button.configuration?.image = UIImage(systemName: symbol)
      button.accessibilityLabel = title
    #else
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      button.toolTip = title
    #endif
  }

  private func make(target: AnyObject, action: Selector) -> FigureButton {
    #if canImport(UIKit)
      var configuration = UIButton.Configuration.glass()
      // A capsule in a square frame: a circle.
      configuration.cornerStyle = .capsule
      configuration.contentInsets = .zero
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 10, weight: .medium)
      configuration.baseForegroundColor = .secondaryLabel
      let button = FigureButton(configuration: configuration)
      button.addTarget(target, action: action, for: .primaryActionTriggered)
    #else
      let button = FigureButton()
      // Glass, in a square frame: a circle.
      button.bezelStyle = .glass
      button.borderShape = .circle
      button.controlSize = .small
      button.imagePosition = .imageOnly
      button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
      button.contentTintColor = .secondaryLabelColor
      button.target = target
      button.action = action
    #endif
    return button
  }
}

extension RFCTextViewCoordinator {
  /// Lays the buttons over the blocks that show one now: on iOS those whose first
  /// line is on screen, on macOS the one the pointer is over. Called whenever the
  /// text moves under them or the pointer moves over it.
  func updateFigureControls() {
    guard let textView, let built, let layout = textView.textLayoutManager else { return }
    #if !canImport(UIKit)
      figureControls.hovered = textView.window.flatMap {
        figureBlock(atWindowPoint: $0.mouseLocationOutsideOfEventStream)
      }
    #endif
    let origin = containerOrigin(of: textView)
    var wanted: [(control: FigureControl.Control, frame: CGRect)] = []
    // None while a resize waits for its rebuild, which places them again: the
    // frames they would be placed by belong to the old column (#546).
    for block in figureControls.blocks where !columnAwaitsRebuild && showsFigureControl(of: block) {
      guard
        let location = layout.location(
          layout.documentRange.location, offsetBy: block.location),
        let fragment = layout.textLayoutFragment(for: location),
        let range = layout.range(of: fragment.rangeInElement),
        let rect = Self.figureControlRect(of: fragment, range: range, in: built.text)
      else { continue }
      wanted.append((block.control, rect.offsetBy(dx: origin.x, dy: origin.y)))
    }
    figureControls.show(
      wanted, over: textView, target: self, action: #selector(pressedFigureControl(_:)))
  }

  /// A block's button in text-container coordinates, from its first fragment.
  nonisolated static func figureControlRect(
    of fragment: NSTextLayoutFragment, range: NSRange, in text: NSAttributedString
  ) -> CGRect? {
    guard let span = FragmentGeometry.decorationSpan(in: text, fragment: range) else {
      return nil
    }
    let frame = fragment.layoutFragmentFrame
    let placement = FragmentGeometry.Placement(
      origin: frame.origin, frame: frame,
      containerWidth: fragment.textLayoutManager?.textContainer?.size.width ?? frame.width,
      indent: span.indent, contentWidth: span.contentWidth)
    return FigureControl.rect(
      inCard: placement.cardRect(padding: FragmentGeometry.cardPadding, span: span))
  }

  /// Shows the block's other presentation.
  @objc func pressedFigureControl(_ sender: FigureButton) {
    onToggleSource(sender.tag)
  }

  private func containerOrigin(of textView: PlatformTextView) -> CGPoint {
    #if canImport(UIKit)
      CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
    #else
      // From the inset, which `layOut` has just set, rather than
      // `textContainerOrigin`, which AppKit brings up to date only when it next lays
      // the view out: during a live resize, a frame late.
      CGPoint(x: textView.textContainerInset.width, y: textView.textContainerInset.height)
    #endif
  }

  #if canImport(UIKit)
    /// Whether a block's first line is between the viewport's top and bottom.
    private func showsFigureControl(of block: FigureControl.Block) -> Bool {
      guard let textView, let layout = textView.textLayoutManager else { return false }
      let top = max(0, textView.viewportTop)
      guard
        let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)),
        let last = layout.textLayoutFragment(
          for: CGPoint(x: 0, y: top + textView.viewportHeight))
      else { return false }
      return layout.offset(of: first.rangeInElement.location) <= block.location
        && block.location < layout.offset(of: last.rangeInElement.endLocation)
    }
  #else
    private func showsFigureControl(of block: FigureControl.Block) -> Bool {
      block.control.ordinal == figureControls.hovered
    }

    /// The block with a button under a point in window coordinates: its lines, or
    /// the button showing for it, which reaches above its first line.
    private func figureBlock(atWindowPoint point: NSPoint) -> Int? {
      guard let textView, let built, let layout = textView.textLayoutManager,
        let window = textView.window,
        // A window of another app over this one hides the pointer from it.
        NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
          == window.windowNumber
      else { return nil }
      let viewPoint = textView.convert(point, from: nil)
      guard textView.visibleRect.contains(viewPoint),
        headerHost?.view.frame.contains(viewPoint) != true
      else { return nil }
      if figureControls.frame(of: figureControls.hovered)?.contains(viewPoint) == true {
        return figureControls.hovered
      }
      let origin = containerOrigin(of: textView)
      guard
        let fragment = layout.textLayoutFragment(
          for: CGPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y))
      else { return nil }
      return FigureControl.ordinal(
        at: layout.offset(of: fragment.rangeInElement.location), in: built.text)
    }
  #endif
}
