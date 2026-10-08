import RFCReaderKit
import Synchronization

#if !canImport(UIKit)
  import AppKit

  // A heading's hung number (#433), on macOS: under the pointer it comes up to the
  // label's color with a help tag, and an Option-click copies a link to the heading,
  // with a badge over the number that fades. A plain click is the text view's, which
  // follows the number's link to its heading. Where the number is and what it links
  // to are the build's (`sectionNumber(at:)`); this is the pointer and the feedback.
  // The badge is a view over the text rather than a change to it, which no text view
  // may write to: a kept build is installed into more than one.

  extension RFCTextViewCoordinator {
    private static let linkCopiedIdentifier = NSUserInterfaceItemIdentifier("linkCopiedBadge")
    private static let badgeHoldDuration: TimeInterval = 1.2
    private static let badgeFadeDuration: TimeInterval = 0.6

    /// The hung number under the pointer of `event`: the heading it links to, and
    /// its extent.
    private func sectionNumber(under event: NSEvent) -> (anchor: String, range: NSRange)? {
      guard let textView, event.window === textView.window,
        let text = textView.textLayoutManager?.attributedText
      else { return nil }
      let viewPoint = textView.convert(event.locationInWindow, from: nil)
      let containerPoint = CGPoint(
        x: viewPoint.x - textView.textContainerOrigin.x,
        y: viewPoint.y - textView.textContainerOrigin.y)
      guard let offset = characterOffset(atContainerPoint: containerPoint) else { return nil }
      return text.sectionNumber(at: offset)
    }

    /// Lights up the number under the pointer of `event`, and puts out the one it
    /// left; nil when the pointer left the text.
    func hoverSectionNumber(under event: NSEvent?) {
      let hovered = event.flatMap { sectionNumber(under: $0) }?.range
      let previous = hoveredSectionNumber.withLock { current in
        defer { current = hovered }
        return current
      }
      guard previous != hovered, let textView, let layout = textView.textLayoutManager else {
        return
      }
      for range in [previous, hovered].compactMap(\.self) {
        if let textRange = layout.textRange(for: range) {
          layout.invalidateRenderingAttributes(for: textRange)
        }
      }
      textView.needsDisplay = true
      textView.toolTip = hovered == nil ? nil : String(localized: "Option-click to copy link")
    }

    /// Copies a link to the heading whose number is under the pointer of `event`, as
    /// Copy Link in its menu does: the RFC Editor's URL, which the app opens too.
    /// Answers whether there was a number.
    func copySectionLink(under event: NSEvent) -> Bool {
      guard let documentID, let number = sectionNumber(under: event),
        let url = DocumentTextBuilder.url(number.anchor, scheme: DocumentTextBuilder.anchorScheme),
        let link = LinkCopy.forLink(
          url, from: documentID, in: environment?.library.index, bibliography: bibliography)
      else { return false }
      Clipboard.write(.link(link), announcing: .link)
      showLinkCopied(over: number.range)
      return true
    }

    private func showLinkCopied(over range: NSRange) {
      guard let textView, let rect = referenceRect(for: range) else { return }
      for view in textView.subviews where view.identifier == Self.linkCopiedIdentifier {
        view.removeFromSuperview()
      }
      let label = NSTextField(labelWithString: CopyFeedback.link.announcement())
      label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
      label.textColor = RFCColors.label
      label.sizeToFit()
      let padding = CGSize(width: 8, height: 3)
      let size = CGSize(
        width: label.frame.width + padding.width * 2,
        height: label.frame.height + padding.height * 2)
      let origin = textView.textContainerOrigin
      // Above the number, its trailing edge on the number's: the badge is wider than
      // a number, and the gutter is to its left.
      let badge = NSView(
        frame: CGRect(
          x: origin.x + rect.maxX - size.width, y: origin.y + rect.minY - size.height - 2,
          width: size.width, height: size.height))
      badge.identifier = Self.linkCopiedIdentifier
      badge.wantsLayer = true
      badge.layer?.cornerRadius = size.height / 2
      badge.layer?.masksToBounds = true
      // Opaque, so the heading's text does not show through: the page, and a card's
      // tint over it, as a code block's copy feedback is drawn.
      textView.effectiveAppearance.performAsCurrentDrawingAppearance {
        badge.layer?.backgroundColor = textView.backgroundColor.cgColor
        let tint = CALayer()
        tint.frame = badge.bounds
        tint.backgroundColor = paletteBox.palette.cardFill.cgColor
        badge.layer?.addSublayer(tint)
      }
      label.frame.origin = CGPoint(x: padding.width, y: padding.height)
      badge.addSubview(label)
      textView.addSubview(badge)

      Task { [weak badge] in
        try? await Task.sleep(for: .seconds(Self.badgeHoldDuration))
        await NSAnimationContext.runAnimationGroup { context in
          context.duration = Self.badgeFadeDuration
          badge?.animator().alphaValue = 0
        }
        badge?.removeFromSuperview()
      }
    }
  }
#endif
