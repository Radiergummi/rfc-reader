import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The views over a reader's index: its current group's letter pinned at the top, and
/// the A–Z rail. Made the first time an index shows; placed by the coordinator on every
/// viewport report from `IndexOverlay`'s functions. Over the text, never in it: the
/// body stays one text storage.
final class IndexOverlayController {
  /// The index's top-level entries' keys, in order, for type-select.
  private(set) var keys: [String] = []
  var typeSelect = IndexTypeSelect()
  private(set) var isShowing = false
  private var groupLabels: [NSAttributedString] = []
  /// The pinned letter's height, and the column width it was measured at: measured
  /// once per build and width, not per scroll tick.
  private var measured: (width: CGFloat, height: CGFloat)?
  private var sticky: PlatformLabel?
  private(set) var rail: IndexRailView?

  /// The groups' letters, which the rail is made with.
  private var labels: [String] = []
  /// Where a tap or drag on the rail goes: to the group's letter.
  private var onSelect: (Int) -> Void = { _ in }

  /// A new build: what it knows of its index, and nothing shown until it is placed.
  func installed(_ built: BuiltDocument, onSelect: @escaping (Int) -> Void) {
    let map = built.indexMap
    labels = map.groups.map(\.label)
    self.onSelect = onSelect
    keys = map.entries.map(\.key)
    typeSelect = IndexTypeSelect()
    groupLabels = map.groups.map { group in
      // The letter as the text sets it, without what makes it a paragraph or a heading.
      let label = NSMutableAttributedString(
        attributedString: built.text.attributedSubstring(from: group.labelRange))
      let whole = NSRange(location: 0, length: label.length)
      for key: NSAttributedString.Key in [.paragraphStyle, .rfcAnchor] {
        label.removeAttribute(key, range: whole)
      }
      return label
    }
    rail?.labels = labels
    rail?.onSelect = onSelect
    measured = nil
    hide()
  }

  func hide() {
    isShowing = false
    sticky?.isHidden = true
    rail?.isHidden = true
  }

  /// Shows the overlays in `host` (iOS: the text view; macOS: its scroll view): the
  /// letter of `group` at `stickyFrame`, or none, and `layout` at `railFrame`, both in
  /// the host's own coordinates.
  func show(
    in host: PlatformView, stickyFrame: CGRect?, group: Int?, layout: IndexRail, railFrame: CGRect
  ) {
    isShowing = true
    let rail = rail ?? makeRail(in: host)
    rail.currentGroup = group
    rail.layout = layout
    rail.frame = railFrame
    rail.isHidden = false
    guard let stickyFrame, let group, groupLabels.indices.contains(group) else {
      sticky?.isHidden = true
      return
    }
    let sticky = sticky ?? makeSticky(in: host)
    #if canImport(UIKit)
      sticky.attributedText = groupLabels[group]
    #else
      sticky.attributedStringValue = groupLabels[group]
    #endif
    sticky.frame = stickyFrame
    sticky.isHidden = false
  }

  /// The pinned letter's height, as its label measures for `width`.
  func stickyHeight(width: CGFloat) -> CGFloat {
    if let measured, measured.width == width { return measured.height }
    guard let label = groupLabels.first else { return 0 }
    #if canImport(UIKit)
      let probe = UILabel()
      probe.attributedText = label
      let fitted = probe.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
      let height = ceil(fitted.height) + 8
    #else
      let height = ceil(NSTextField(labelWithAttributedString: label).fittingSize.height) + 8
    #endif
    measured = (width, height)
    return height
  }

  private func makeRail(in host: PlatformView) -> IndexRailView {
    let rail = IndexRailView()
    rail.labels = labels
    rail.onSelect = onSelect
    #if canImport(UIKit)
      rail.backgroundColor = .clear
      rail.layer.zPosition = 1
      host.addSubview(rail)
    #else
      host.addSubview(rail, positioned: .above, relativeTo: (host as? NSScrollView)?.contentView)
    #endif
    self.rail = rail
    return rail
  }

  private func makeSticky(in host: PlatformView) -> PlatformLabel {
    #if canImport(UIKit)
      let label = UILabel()
      label.backgroundColor = RFCColors.page
      label.isAccessibilityElement = false
      label.layer.zPosition = 1
      host.addSubview(label)
    #else
      let label = NSTextField(labelWithString: "")
      label.drawsBackground = true
      label.backgroundColor = RFCColors.page
      label.setAccessibilityElement(false)
      host.addSubview(label, positioned: .above, relativeTo: (host as? NSScrollView)?.contentView)
    #endif
    sticky = label
    return label
  }
}

#if canImport(UIKit)
  typealias PlatformView = UIView
  typealias PlatformLabel = UILabel
#else
  typealias PlatformView = NSView
  typealias PlatformLabel = NSTextField
#endif
