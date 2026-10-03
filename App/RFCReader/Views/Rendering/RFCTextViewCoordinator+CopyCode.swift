import RFCReaderKit

#if !canImport(UIKit)
  import AppKit

  // A code block's copy button (macOS): a click copies the block, and the button
  // shows a checkmark for a moment. What it copies and where it is are
  // `copyButton(at:)` and `code(ofCopyButtonAt:)`; this is the click and the
  // feedback. The checkmark is a view over the button rather than a change to the
  // text, which no text view may write to: a kept build is installed into more
  // than one.

  extension RFCTextViewCoordinator {
    private static let feedbackIdentifier = NSUserInterfaceItemIdentifier("copyCodeFeedback")
    private static let fadeInDuration: TimeInterval = 0.2
    private static let holdDuration: TimeInterval = 2
    private static let fadeOutDuration: TimeInterval = 0.6

    /// Whether a copy button is under the pointer of `event`. Asked on every
    /// pointer move, so it only looks; the code is worked out on a click.
    func isOverCopyButton(_ event: NSEvent) -> Bool {
      guard let hit = textOffset(under: event) else { return false }
      return hit.text.copyButton(at: hit.offset) != nil
    }

    /// Copies the block whose button is under the pointer of `event`; answers
    /// whether there was one.
    func copyCode(under event: NSEvent) -> Bool {
      guard let hit = textOffset(under: event),
        let range = hit.text.copyButton(at: hit.offset),
        let code = hit.text.code(ofCopyButtonAt: hit.offset)
      else { return false }
      Clipboard.copy(code)
      showCopied(over: range)
      return true
    }

    /// The text and the character offset under the pointer of `event`, or nil.
    private func textOffset(under event: NSEvent) -> (text: NSAttributedString, offset: Int)? {
      guard let textView, event.window === textView.window,
        let text = textView.textLayoutManager?.attributedText
      else { return nil }
      let viewPoint = textView.convert(event.locationInWindow, from: nil)
      let containerPoint = CGPoint(
        x: viewPoint.x - textView.textContainerOrigin.x,
        y: viewPoint.y - textView.textContainerOrigin.y)
      guard let offset = characterOffset(atContainerPoint: containerPoint) else { return nil }
      return (text, offset)
    }

    private func showCopied(over range: NSRange) {
      guard let textView, let rect = referenceRect(for: range) else { return }
      for view in textView.subviews where view.identifier == Self.feedbackIdentifier {
        view.removeFromSuperview()
      }
      let frame = rect.offsetBy(
        dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y
      )
      .insetBy(dx: -2, dy: -2)
      let feedback = NSView(frame: frame)
      feedback.identifier = Self.feedbackIdentifier
      feedback.wantsLayer = true
      // Opaque, so the button does not show through: the page, and the card's tint
      // over it, as the card draws.
      textView.effectiveAppearance.performAsCurrentDrawingAppearance {
        feedback.layer?.backgroundColor = textView.backgroundColor.cgColor
        let tint = CALayer()
        tint.frame = feedback.bounds
        tint.backgroundColor = RFCColors.cardFill.cgColor
        feedback.layer?.addSublayer(tint)
      }
      let font =
        textView.textLayoutManager?.attributedText?.attribute(
          .font, at: range.location, effectiveRange: nil) as? NSFont
      let checkmark = NSImageView(frame: feedback.bounds)
      checkmark.image = NSImage(
        systemSymbolName: "checkmark", accessibilityDescription: nil)
      checkmark.symbolConfiguration = .init(
        pointSize: (font?.pointSize ?? rect.height * 0.7) * DocumentTextBuilder.copyButtonScale,
        weight: .regular)
      checkmark.contentTintColor = RFCColors.secondaryLabel
      feedback.addSubview(checkmark)
      feedback.alphaValue = 0
      textView.addSubview(feedback)
      NSAccessibility.post(
        element: textView, notification: .announcementRequested,
        userInfo: [.announcement: "Copied"])

      // Faded in and out rather than switched, so the change reads as a response to
      // the click and not as a flicker.
      Task { [weak feedback] in
        await NSAnimationContext.runAnimationGroup { context in
          context.duration = Self.fadeInDuration
          feedback?.animator().alphaValue = 1
        }
        try? await Task.sleep(for: .seconds(Self.holdDuration))
        await NSAnimationContext.runAnimationGroup { context in
          context.duration = Self.fadeOutDuration
          feedback?.animator().alphaValue = 0
        }
        feedback?.removeFromSuperview()
      }
    }
  }
#endif
