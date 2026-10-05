import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension RFCTextViewCoordinator {
  /// Shows, places or hides the index's overlays for where the viewport is. Called on
  /// every viewport report and after a layout. A preview's reader shows none.
  func updateIndexOverlay() {
    guard commitsOnClick == nil, let textView, let layout = textView.textLayoutManager,
      let built, let column = laidOutColumn, !built.indexMap.isEmpty,
      let visible = visibleRange(in: textView),
      built.indexMap.isShowing(visible: visible, hidden: foldingDelegate.hidden)
    else {
      indexOverlay.hide()
      return
    }
    let map = built.indexMap
    let top = textView.viewportTop
    let group = map.group(at: visible.location)
    func labelTop(_ group: Int?) -> CGFloat? {
      guard let group, map.groups.indices.contains(group),
        NSIntersectionRange(visible, map.groups[group].labelRange).length > 0,
        let location = layout.location(atOffset: map.groups[group].labelRange.location),
        let fragment = layout.textLayoutFragment(for: location),
        // Under viewport layout a fragment can be found before it is laid out, its
        // frame still at the top of the document; that is no answer.
        fragment.state == .layoutAvailable
      else { return nil }
      return fragment.layoutFragmentFrame.minY - top
    }
    let height = indexOverlay.stickyHeight(width: column)
    let offset = group.flatMap {
      StickyLetter.offset(
        currentLabelTop: labelTop($0), nextLabelTop: labelTop($0 + 1), height: height)
    }
    let available = textView.viewportHeight - 2 * ReaderLayout.margin
    let rail = IndexRail(labels: map.groups.map(\.label), available: available)
    let railTop = (textView.viewportHeight - rail.height) / 2
    #if canImport(UIKit)
      let originY = textView.unobscuredTop
      let centerX = IndexRail.centerX(
        viewWidth: textView.bounds.width, column: column,
        trailingObstruction: textView.safeAreaInsets.right)
      indexOverlay.show(
        in: textView,
        stickyFrame: offset.map {
          CGRect(
            x: textView.textContainerInset.left, y: originY + $0, width: column, height: height)
        },
        group: group, layout: rail,
        railFrame: CGRect(
          x: centerX - IndexRail.width / 2, y: originY + railTop, width: IndexRail.width,
          height: rail.height))
    #else
      guard let scrollView = textView.enclosingScrollView else { return }
      let insetTop = scrollView.contentView.contentInsets.top
      let scroller =
        scrollView.scrollerStyle == .overlay
        ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay) : 0
      let centerX = IndexRail.centerX(
        viewWidth: scrollView.bounds.width, column: column, trailingObstruction: scroller)
      // Flipped for a scroll view that is not: frames below are measured from its top.
      func fromTop(_ y: CGFloat, height: CGFloat) -> CGFloat {
        scrollView.isFlipped ? y : scrollView.bounds.height - y - height
      }
      indexOverlay.show(
        in: scrollView,
        stickyFrame: offset.map {
          CGRect(
            x: textView.textContainerOrigin.x, y: fromTop(insetTop + $0, height: height),
            width: column, height: height)
        },
        group: group, layout: rail,
        railFrame: CGRect(
          x: centerX - IndexRail.width / 2, y: fromTop(insetTop + railTop, height: rail.height),
          width: IndexRail.width, height: rail.height))
    #endif
  }

  /// The characters from the top of the viewport's uncovered part to its bottom, read
  /// from the fragments there, as the running heading reads the top one.
  private func visibleRange(in textView: PlatformTextView) -> NSRange? {
    guard let layout = textView.textLayoutManager else { return nil }
    let top = max(textView.viewportTop, 0)
    guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return nil }
    let start = layout.offset(of: first.rangeInElement.location)
    let bottom = layout.textLayoutFragment(for: CGPoint(x: 0, y: top + textView.viewportHeight))
    let end =
      bottom.map { layout.offset(of: $0.rangeInElement.endLocation) } ?? built?.text.length ?? start
    return NSRange(location: start, length: max(end - start, 0))
  }

  /// Puts a group's letter at the top, from the rail.
  func jumpToIndexGroup(_ group: Int) {
    guard let built, built.indexMap.groups.indices.contains(group) else { return }
    let offset = built.indexMap.groups[group].labelRange.location
    if !show(offset) {
      engine.jump(toOffset: offset)
    }
    reportVisibleAnchor()
  }
}
