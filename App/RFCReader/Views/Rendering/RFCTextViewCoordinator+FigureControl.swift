import RFCReaderKit
import os

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Which rendered block the pointer is over, for the fragments to draw its Figure |
/// Source control (macOS; iOS always shows it). Read by fragments as they draw,
/// which TextKit may do off the main thread, so behind a lock.
nonisolated final class FigureHover: Sendable {
  private let ordinal = OSAllocatedUnfairLock<Int?>(initialState: nil)

  var current: Int? { ordinal.withLock { $0 } }

  /// Whether the hovered block changed.
  func set(_ new: Int?) -> Bool {
    ordinal.withLock { value in
      guard value != new else { return false }
      value = new
      return true
    }
  }
}

extension RFCTextViewCoordinator {
  /// The control under a point in text-container coordinates, and the segment it
  /// hits: where `FigureControl` says it is drawn in the card of the fragment the
  /// point is in.
  func figureControl(atContainerPoint point: CGPoint) -> (
    control: FigureControl.Control, segment: FigureControl.Segment
  )? {
    guard let text = textView?.textStorage, let layout = textView?.textLayoutManager,
      let fragment = layout.textLayoutFragment(for: point),
      let range = layout.range(of: fragment.rangeInElement),
      let control = FigureControl.control(atFragment: range, in: text),
      let rect = Self.figureControlRect(of: fragment, range: range, in: text),
      let segment = FigureControl.segment(at: point, in: rect)
    else { return nil }
    return (control, segment)
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

  /// Shows the other presentation when `segment` is not the one on.
  func pressFigureControl(_ control: FigureControl.Control, _ segment: FigureControl.Segment) {
    guard segment != control.shown else { return }
    onToggleSource(control.ordinal)
  }
}

#if canImport(AppKit) && !canImport(UIKit)
  extension RFCTextViewCoordinator {
    private func containerPoint(ofWindowPoint point: NSPoint) -> CGPoint? {
      guard let textView else { return nil }
      let viewPoint = textView.convert(point, from: nil)
      return CGPoint(
        x: viewPoint.x - textView.textContainerOrigin.x,
        y: viewPoint.y - textView.textContainerOrigin.y)
    }

    /// A click on a block's control, taken before `NSTextView` starts a selection.
    /// Answers whether it took the click.
    func clickFigureControl(_ event: NSEvent) -> Bool {
      guard event.clickCount == 1, event.window === textView?.window,
        let point = containerPoint(ofWindowPoint: event.locationInWindow),
        let (control, segment) = figureControl(atContainerPoint: point)
      else { return false }
      pressFigureControl(control, segment)
      return true
    }

    /// Notes which rendered block the pointer is over, and redraws the first line of
    /// the one it left and the one it entered, where the control is drawn. Answers
    /// whether the pointer is on a control, for the cursor.
    func hoverFigureControl(_ event: NSEvent) -> Bool {
      guard let textView, let text = textView.textStorage, let layout = textView.textLayoutManager,
        let point = containerPoint(ofWindowPoint: event.locationInWindow)
      else { return false }
      var hovered: Int?
      if let fragment = layout.textLayoutFragment(for: point),
        let range = layout.range(of: fragment.rangeInElement), range.location < text.length,
        text.attribute(.rfcFigureControl, at: range.location, effectiveRange: nil) != nil,
        let box = text.attribute(.rfcVerbatim, at: range.location, effectiveRange: nil)
          as? VerbatimBox
      {
        hovered = box.ordinal
      }
      let previous = figureHover.current
      if figureHover.set(hovered) {
        for ordinal in [previous, hovered].compactMap(\.self) {
          redrawFigureControl(ofBlock: ordinal, in: text)
        }
      }
      return figureControl(atContainerPoint: point) != nil
    }

    func endFigureHover() {
      guard let text = textView?.textStorage, let previous = figureHover.current,
        figureHover.set(nil)
      else { return }
      redrawFigureControl(ofBlock: previous, in: text)
    }

    /// Redraws the first line of the block numbered `ordinal`.
    private func redrawFigureControl(ofBlock ordinal: Int, in text: NSAttributedString) {
      guard let textView, let layout = textView.textLayoutManager else { return }
      var first: NSRange?
      text.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: text.length)) {
        value, range, stop in
        guard (value as? VerbatimBox)?.ordinal == ordinal else { return }
        first = (text.string as NSString).paragraphRange(
          for: NSRange(location: range.location, length: 0))
        stop.pointee = true
      }
      guard let first, let textRange = layout.textRange(for: first) else { return }
      layout.invalidateRenderingAttributes(for: textRange)
      if let fragment = layout.textLayoutFragment(for: textRange.location) {
        let frame = fragment.renderingSurfaceBounds.offsetBy(
          dx: fragment.layoutFragmentFrame.minX + textView.textContainerOrigin.x,
          dy: fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y)
        textView.setNeedsDisplay(frame)
      }
    }
  }
#endif
