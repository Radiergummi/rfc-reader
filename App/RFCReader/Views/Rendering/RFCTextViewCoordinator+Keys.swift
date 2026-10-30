import RFCKit
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// The reader's keys (#711): Space and Shift-Space, Tab through the links, and the
// vim-style keys, pressed in the reader's text, and Next and Previous Section from
// the menus. What a key means is `ReaderKeys`', where it is pinned by tests; this
// carries it out.

extension RFCTextViewCoordinator {
  /// A key pressed in the reader's text, without ⌘, ⌃ or a chord's ⌥: true where it was the
  /// reader's, and the text view is to do nothing more with it.
  func handleKey(_ key: ReaderKeys.Key) -> Bool {
    // A preview's clicks commit it, and its keys are nobody's.
    guard commitsOnClick == nil else { return false }
    if let link = focusedLink,
      !LinkFocus.keeps(link, on: visibleRange, hidden: foldingDelegate.hidden)
    {
      focus(link: nil)
    }
    let outcome = keys.press(
      key, at: ProcessInfo.processInfo.systemUptime,
      options: ReaderSettings(defaults: .standard).keys, focusesLink: focusedLink != nil)
    switch outcome {
    case .command(let command): return perform(command)
    case .pending: return true
    case .unhandled: return false
    }
  }

  /// Carries out `command`: false where there was nothing to do, as for Tab past
  /// the last link, which the text view then moves the focus on from.
  @discardableResult
  func perform(_ command: ReaderKeyCommand) -> Bool {
    guard let textView, built != nil else { return false }
    switch command {
    case .scroll(let scroll):
      let distance = scroll.distance(viewport: textView.viewportHeight, line: lineHeight)
      engine.scroll(toContainerY: textView.viewportTop + distance)
      reportVisibleAnchor()
    case .top:
      engine.jumpToTop()
      reportVisibleAnchor()
    case .end:
      // As ⌘↓ does: through the engine's reveal, which lays out the way there.
      let length = textView.textLayoutManager?.attributedText?.length ?? 0
      textView.scrollRangeToVisible(NSRange(location: length, length: 0))
    case .section(let step):
      return stepSection(step)
    case .find, .findNext, .findPrevious:
      find(command)
    case .link(let step):
      return focusLink(step)
    case .followLink:
      guard let link = focusedLink else { return false }
      focus(link: nil)
      followLink(at: link.location)
    case .previewLink:
      // A link with nothing to preview, a web page's, leaves Space its page.
      guard let link = focusedLink, previewLink(at: link.location) else {
        return perform(.scroll(.pageDown))
      }
    case .leaveLink:
      focus(link: nil)
    }
    return true
  }

  /// Next or Previous Section: in Focus the focus steps, and anywhere else the reader
  /// goes to the heading `Folding.section(_:fromLine:in:)` names. A move within the
  /// document, as a page is, so it scrolls as a restored place does and leaves no
  /// entry for Back; Go to Section, a jump, leaves one.
  private func stepSection(_ step: Folding.FocusStep) -> Bool {
    if folding.mode == .focus {
      guard let reader = environment?.reader, reader.canStepFocus(step) else { return false }
      reader.stepFocus(step)
      return true
    }
    guard let foldingIndex,
      let anchor = folding.section(step, fromLine: engine.placeOffset, in: foldingIndex)
    else { return false }
    scroll(to: anchor, offset: 0)
    return true
  }

  /// The height of the line at the top of the viewport, which a page keeps in view.
  private var lineHeight: CGFloat {
    guard let textView, let layout = textView.textLayoutManager,
      let line = layout.textLayoutFragment(for: CGPoint(x: 0, y: max(0, textView.viewportTop)))?
        .textLineFragments.first
    else { return 20 }
    return line.typographicBounds.height
  }

  /// The characters on screen, from the layout fragment at the top of the visible
  /// rect to the one at its bottom: where the focus starts when no link has it. Not
  /// TextKit's viewport range, which reaches past both edges.
  private var visibleRange: NSRange {
    guard let textView, let layout = textView.textLayoutManager else {
      return NSRange(location: 0, length: 0)
    }
    // Above the container is the header, where no fragment is: at the top of a
    // document the screen starts with the text's first line. Below the last line,
    // it ends with the text.
    let top = max(0, textView.viewportTop)
    let start =
      layout.textLayoutFragment(for: CGPoint(x: 0, y: top))
      .map { layout.offset(of: $0.rangeInElement.location) } ?? 0
    let end =
      layout.textLayoutFragment(for: CGPoint(x: 0, y: top + textView.viewportHeight))
      .map { layout.offset(of: $0.rangeInElement.endLocation) }
      ?? layout.offset(of: layout.documentRange.endLocation)
    return NSRange(location: max(0, start), length: max(0, end - start))
  }

  /// Moves the focus to the next or previous link, and scrolls it into view. Past
  /// the last one, or before the first, the focus leaves the links.
  private func focusLink(_ step: Folding.FocusStep) -> Bool {
    guard let text = textView?.textLayoutManager?.attributedText,
      let link = LinkFocus.link(
        step, from: focusedLink, on: visibleRange, in: text, hidden: foldingDelegate.hidden)
    else {
      focus(link: nil)
      return false
    }
    focus(link: link)
    textView?.scrollRangeToVisible(link)
    return true
  }

  /// Rings `link`, or nothing, in place of the link ringed before.
  func focus(link: NSRange?) {
    guard link != focusedLink else { return }
    foldingDelegate.focus(link: link)
    // Drawn again, not laid out again: the ring changes no line.
    engine.redraw()
  }

  #if canImport(UIKit)
    private func find(_ command: ReaderKeyCommand) {
      guard let interaction = textView?.findInteraction else { return }
      switch command {
      case .findNext: interaction.findNext()
      case .findPrevious: interaction.findPrevious()
      default: interaction.presentFindNavigator(showingReplace: false)
      }
    }

    /// What a tap on the link does (`textView(_:primaryActionFor:defaultAction:)`).
    private func followLink(at offset: Int) {
      if backlinkCaption(at: offset) != nil { return showBacklinks(at: offset) }
      if errataChip(at: offset) != nil { return showErrata(at: offset) }
      guard let url = link(at: offset) else { return }
      if !onLink(url, .here) { UIApplication.shared.open(url) }
    }

    /// The reference's card in a popover beside it, as a backlink caption's list is;
    /// a backlink caption and an errata chip show their lists, which is what they
    /// have to preview.
    private func previewLink(at offset: Int) -> Bool {
      if backlinkCaption(at: offset) != nil {
        showBacklinks(at: offset)
        return true
      }
      if errataChip(at: offset) != nil {
        showErrata(at: offset)
        return true
      }
      guard let environment, let (box, range) = reference(at: offset),
        let preview = preview(for: box.reference)
      else { return false }
      let host = UIHostingController(rootView: AnyView(preview.readerEnvironment(environment)))
      return presentPopover(host, width: ReferencePreview.width, pointingAt: range)
    }
  #else
    private func find(_ command: ReaderKeyCommand) {
      let action: FindCommand =
        switch command {
        case .findNext: .nextMatch
        case .findPrevious: .previousMatch
        default: .showFindInterface
        }
      textView?.performTextFinderAction(action)
    }

    /// What a click on the link does, through the text view's delegate.
    private func followLink(at offset: Int) {
      guard let textView,
        let link = textView.textLayoutManager?.attributedText?.attribute(
          .link, at: offset, effectiveRange: nil)
      else { return }
      textView.clicked(onLink: link, at: offset)
    }

    /// What the link menu's Preview shows: a reference's card or the document it
    /// names; a backlink caption and an errata chip show their lists.
    private func previewLink(at offset: Int) -> Bool {
      if backlinkCaption(at: offset) != nil {
        showBacklinks(at: offset)
        return true
      }
      if errataChip(at: offset) != nil {
        showErrata(at: offset)
        return true
      }
      guard let forceClick = forceClick(at: offset) else { return false }
      // A card stays, as the menu's does: no pointer is on the reference to leave it.
      if case .forceClickCard(let target) = forceClick {
        hover.send(.cardChosen(target))
      } else {
        hover.send(forceClick)
      }
      return true
    }
  #endif
}
