import RFCReaderKit

#if canImport(UIKit)
  import UIKit

  typealias PlatformSegmentedControl = UISegmentedControl
#else
  import AppKit

  typealias PlatformSegmentedControl = NSSegmentedControl
#endif

/// The Figure | Source controls, native segmented controls laid over the text view
/// in the strip the builder reserves above a rendered block's first line, where no
/// text is. Subviews of the text view, so they scroll with it; placed again only
/// when the text moves under them. A print or an export draws fragments alone, so
/// never shows one.
///
/// On iOS every block whose first line is on screen shows its control; on macOS only
/// the one the pointer is over, fading in dimmed and brightening under the pointer,
/// so a page of diagrams is neither covered in controls nor shouting.
final class FigureControls {
  /// The installed document's blocks that have a control.
  var blocks: [FigureControl.Block] = []
  /// The block the pointer is over, on macOS.
  var hovered: Int?
  /// Whether the pointer is on that block's control itself, which then shows at
  /// full strength rather than dimmed.
  var pointerOnControl = false
  /// Showing, by the ordinal of the block each belongs to.
  private var placed: [Int: PlatformSegmentedControl] = [:]
  private var spare: [PlatformSegmentedControl] = []
  /// How strongly a macOS control shows while the pointer is over its block but
  /// not on it.
  private static let restingAlpha: CGFloat = 0.5

  func frame(of ordinal: Int?) -> CGRect? {
    ordinal.flatMap { placed[$0]?.frame }
  }

  /// Shows a control at each frame, in the text view's coordinates, and puts away
  /// the rest.
  func show(
    _ wanted: [(control: FigureControl.Control, frame: CGRect)], over view: PlatformTextView,
    target: AnyObject, action: Selector, fades: Bool
  ) {
    let ordinals = Set(wanted.map(\.control.ordinal))
    for (ordinal, segmented) in placed where !ordinals.contains(ordinal) {
      placed[ordinal] = nil
      retire(segmented, fades: fades)
    }
    for (control, frame) in wanted {
      let segmented =
        placed[control.ordinal]
        ?? bringOut(over: view, target: target, action: action, fades: fades)
      segmented.frame = frame
      segmented.tag = control.ordinal
      #if !canImport(UIKit)
        let alpha = pointerOnControl ? 1 : Self.restingAlpha
        if segmented.alphaValue != alpha {
          if fades {
            NSAnimationContext.runAnimationGroup { _ in segmented.animator().alphaValue = alpha }
          } else {
            segmented.alphaValue = alpha
          }
        }
      #endif
      #if canImport(UIKit)
        segmented.selectedSegmentIndex = control.shown == .figure ? 0 : 1
      #else
        segmented.selectedSegment = control.shown == .figure ? 0 : 1
      #endif
      placed[control.ordinal] = segmented
    }
  }

  private func bringOut(
    over view: PlatformTextView, target: AnyObject, action: Selector, fades: Bool
  ) -> PlatformSegmentedControl {
    let segmented = spare.popLast() ?? make(target: target, action: action)
    if segmented.superview !== view { view.addSubview(segmented) }
    segmented.isHidden = false
    return segmented
  }

  /// Hidden, and kept for the next block. A fade ends hidden only if nothing
  /// brought the control out again meanwhile.
  private func retire(_ segmented: PlatformSegmentedControl, fades: Bool) {
    spare.append(segmented)
    #if canImport(UIKit)
      segmented.isHidden = true
    #else
      guard fades else {
        segmented.alphaValue = 0
        segmented.isHidden = true
        return
      }
      NSAnimationContext.runAnimationGroup { _ in
        segmented.animator().alphaValue = 0
      } completionHandler: {
        // AppKit runs it on the main thread.
        MainActor.assumeIsolated {
          if segmented.alphaValue == 0 { segmented.isHidden = true }
        }
      }
    #endif
  }

  private func make(target: AnyObject, action: Selector) -> PlatformSegmentedControl {
    let labels = [FigureControl.Segment.figure, .source].map(FigureControl.label(of:))
    #if canImport(UIKit)
      let segmented = UISegmentedControl(items: labels)
      segmented.setTitleTextAttributes(
        [.font: UIFont.systemFont(ofSize: 10, weight: .medium)], for: .normal)
      segmented.addTarget(target, action: action, for: .valueChanged)
    #else
      let segmented = NSSegmentedControl(
        labels: labels, trackingMode: .selectOne, target: target, action: action)
      segmented.controlSize = .mini
      segmented.font = .systemFont(ofSize: NSFont.systemFontSize(for: .mini))
      // Out from hidden, so the first placement fades it in.
      segmented.alphaValue = 0
    #endif
    return segmented
  }
}

extension RFCTextViewCoordinator {
  /// Lays the controls over the blocks that show one now: on iOS those whose first
  /// line is on screen, on macOS the one the pointer is over. Called whenever the
  /// text moves under them or the pointer moves over it.
  func updateFigureControls(fades: Bool = false) {
    guard let textView, let built, let layout = textView.textLayoutManager else { return }
    #if !canImport(UIKit)
      let pointer = textView.window.flatMap {
        figureBlock(atWindowPoint: $0.mouseLocationOutsideOfEventStream)
      }
      figureControls.hovered = pointer?.ordinal
      figureControls.pointerOnControl = pointer?.onControl ?? false
    #endif
    let origin = containerOrigin(of: textView)
    var wanted: [(control: FigureControl.Control, frame: CGRect)] = []
    for block in figureControls.blocks where showsFigureControl(of: block) {
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
      wanted, over: textView, target: self, action: #selector(pressedFigureControl(_:)),
      fades: fades)
  }

  /// A block's control in text-container coordinates, from its first fragment.
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

  /// Shows the other presentation when the segment pressed is not the one on.
  @objc func pressedFigureControl(_ sender: PlatformSegmentedControl) {
    #if canImport(UIKit)
      let pressed: FigureControl.Segment = sender.selectedSegmentIndex == 0 ? .figure : .source
    #else
      let pressed: FigureControl.Segment = sender.selectedSegment == 0 ? .figure : .source
    #endif
    guard let block = figureControls.blocks.first(where: { $0.control.ordinal == sender.tag }),
      pressed != block.control.shown
    else { return }
    onToggleSource(block.control.ordinal)
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

    /// The block with a control under a point in window coordinates: its lines, or
    /// the control showing for it, which reaches above its first line; and whether
    /// the point is on that control.
    private func figureBlock(atWindowPoint point: NSPoint) -> (ordinal: Int, onControl: Bool)? {
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
      if let hovered = figureControls.hovered,
        figureControls.frame(of: hovered)?.contains(viewPoint) == true
      {
        return (hovered, true)
      }
      let origin = containerOrigin(of: textView)
      guard
        let fragment = layout.textLayoutFragment(
          for: CGPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y))
      else { return nil }
      return FigureControl.ordinal(
        at: layout.offset(of: fragment.rangeInElement.location), in: built.text
      ).map { ($0, false) }
    }
  #endif
}
