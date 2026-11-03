import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The A–Z rail beside an index: draws `IndexRail`'s rows and says which group a tap
/// or drag falls on. One adjustable element to VoiceOver, stepping through the groups.
final class IndexRailView: IndexRailBase {
  var labels: [String] = []
  /// The group the reader is in, which VoiceOver reads as the rail's value.
  var currentGroup: Int?
  var onSelect: (Int) -> Void = { _ in }

  /// The rows drawn and hit-tested, laid out for the height the rail has.
  var layout = IndexRail(labels: [], available: 0) {
    didSet {
      guard layout != oldValue else { return }
      #if canImport(UIKit)
        setNeedsDisplay()
      #else
        needsDisplay = true
      #endif
    }
  }
  private var lastSelected: Int?
  #if canImport(UIKit)
    private let feedback = UISelectionFeedbackGenerator()
  #endif

  private var attributes: [NSAttributedString.Key: Any] {
    [
      .font: PlatformFont.systemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: RFCColors.readerLink,
    ]
  }

  #if canImport(UIKit)
    override func draw(_ rect: CGRect) {
      drawRows()
    }
  #else
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
      drawRows()
    }
  #endif

  private func drawRows() {
    for row in layout.rows {
      let text = NSAttributedString(string: row.text, attributes: attributes)
      let line = CTLineCreateWithAttributedString(text)
      let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
      let lineHeight = (attributes[.font] as? PlatformFont)?.pointSize ?? 11
      text.draw(at: CGPoint(x: (bounds.width - width) / 2, y: row.center - lineHeight * 0.6))
    }
  }

  private func select(at y: CGFloat) {
    guard let group = layout.group(at: y), group != lastSelected else { return }
    lastSelected = group
    #if canImport(UIKit)
      feedback.selectionChanged()
    #endif
    onSelect(group)
  }

  #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      lastSelected = nil
      feedback.prepare()
      if let touch = touches.first { select(at: touch.location(in: self).y) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      if let touch = touches.first { select(at: touch.location(in: self).y) }
    }

    // Not passed on: the text view never saw these touches begin.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    /// Touched further in than it is drawn, as `UITableView`'s section index is: the
    /// rail is narrow beside the text, a finger is not.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
      bounds.insetBy(dx: -Self.touchMargin, dy: 0).contains(point)
    }
    private static let touchMargin: CGFloat = 13

    override var isAccessibilityElement: Bool {
      get { true }
      set {}
    }
    override var accessibilityTraits: UIAccessibilityTraits {
      get { .adjustable }
      set {}
    }
    override var accessibilityLabel: String? {
      get { String(localized: "Index") }
      set {}
    }
    override var accessibilityHint: String? {
      get { String(localized: "Moves through the index by letter.") }
      set {}
    }
    override var accessibilityValue: String? {
      get { currentGroup.map { labels[$0] } }
      set {}
    }
    override func accessibilityIncrement() { step(by: 1) }
    override func accessibilityDecrement() { step(by: -1) }
  #else
    override func mouseDown(with event: NSEvent) {
      lastSelected = nil
      select(at: convert(event.locationInWindow, from: nil).y)
    }

    override func mouseDragged(with event: NSEvent) {
      select(at: convert(event.locationInWindow, from: nil).y)
    }

    override func resetCursorRects() {
      addCursorRect(bounds, cursor: .arrow)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { String(localized: "Index") }
    override func accessibilityHelp() -> String? {
      String(localized: "Moves through the index by letter.")
    }
    override func accessibilityValue() -> Any? { currentGroup.map { labels[$0] } }
    override func accessibilityPerformIncrement() -> Bool {
      step(by: 1)
      return true
    }
    override func accessibilityPerformDecrement() -> Bool {
      step(by: -1)
      return true
    }
  #endif

  private func step(by delta: Int) {
    guard !labels.isEmpty else { return }
    let next = min(max((currentGroup ?? -1) + delta, 0), labels.count - 1)
    currentGroup = next
    onSelect(next)
  }
}

#if canImport(UIKit)
  /// A control, so that the text view, a scroll view, lets a drag that starts on the
  /// rail be the rail's (`touchesShouldCancel(in:)` answers false for a control)
  /// rather than scrolling the text under it.
  typealias IndexRailBase = UIControl
#else
  typealias IndexRailBase = NSView
#endif
