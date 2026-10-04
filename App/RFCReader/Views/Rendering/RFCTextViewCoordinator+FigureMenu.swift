#if canImport(UIKit)
  import RFCReaderKit
  import UIKit
  import UniformTypeIdentifiers

  extension RFCTextViewCoordinator {
    /// The item that shows a block with a rendering as its text, or as its figure,
    /// in its long-press menu and in the edit menu of a selection inside it. Nil for
    /// a block with nothing to switch to, and where the reader cannot switch one.
    func presentationAction(for box: VerbatimBox) -> UIAction? {
      guard let shown = box.presentation, let onChoosePresentation else { return nil }
      let offered = FigureMenu.offered(from: shown)
      return UIAction(
        title: FigureMenu.title(offeredFrom: shown),
        image: UIImage(systemName: FigureMenu.symbol(offeredFrom: shown))
      ) { _ in onChoosePresentation(box.presentationKey, offered) }
    }

    /// The long-press menu of a block with a rendering (`rfcFigureItem`), the way
    /// Photos and Safari handle an image: the figure lifted, as it is drawn, over
    /// Show as Text or Show as Figure, Copy and Share. Copy puts the block's text on
    /// the pasteboard, as Copy Figure does, and the drawing beside it where one
    /// shows; Share hands out what shows, the drawing or the text.
    func figureMenu(for textItem: UITextItem, in textView: UITextView)
      -> UITextItem.MenuConfiguration?
    {
      // The whole block, not the item's range: that is the run under the finger.
      let range =
        FigureMenu.itemRange(at: textItem.range.location, in: textView.textStorage)
        ?? textItem.range
      guard let box = FigureCopy.box(at: range.location, in: textView.textStorage) else {
        return nil
      }
      let text = FigureCopy.pasteboardText(for: box.content)
      let image = figureImage(of: range, in: textView)
      let drawing = box.presentation == .figure ? image : nil
      var children: [UIMenuElement] = []
      if let action = presentationAction(for: box) { children.append(action) }
      children.append(
        UIAction(title: String(localized: "Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
          Clipboard.write(.figure(box.content, png: drawing?.pngData()), announcing: .figure)
        })
      children.append(
        UIAction(
          title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")
        ) {
          [weak textView] _ in
          guard let textView else { return }
          Self.share([drawing ?? text], from: textView, at: range)
        })
      let menu = UIMenu(title: "", children: children)
      guard let image, let window = textView.window else {
        return UITextItem.MenuConfiguration(menu: menu)
      }
      // A wide figure on a narrow screen is lifted smaller, never cut off.
      let fit = min(1, (window.bounds.width - 32) / image.size.width)
      let preview = UIImageView(image: image)
      preview.frame.size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
      return UITextItem.MenuConfiguration(preview: .view(preview), menu: menu)
    }

    /// The block in `range` as it is drawn: its fragments, card and lines and all,
    /// on the page's own background, in the text view's appearance.
    func figureImage(of range: NSRange, in textView: UITextView) -> UIImage? {
      guard let layout = textView.textLayoutManager,
        let start = layout.location(layout.documentRange.location, offsetBy: range.location),
        let end = layout.location(start, offsetBy: range.length)
      else { return nil }
      var fragments: [NSTextLayoutFragment] = []
      layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
        guard fragment.rangeInElement.location.compare(end) == .orderedAscending else {
          return false
        }
        fragments.append(fragment)
        return true
      }
      let bounds = fragments.reduce(CGRect.null) { bounds, fragment in
        let origin = fragment.layoutFragmentFrame.origin
        return bounds.union(fragment.renderingSurfaceBounds.offsetBy(dx: origin.x, dy: origin.y))
      }
      guard !bounds.isNull, !bounds.isEmpty else { return nil }
      let traits = textView.traitCollection
      let renderer = UIGraphicsImageRenderer(
        size: bounds.size, format: UIGraphicsImageRendererFormat(for: traits))
      return renderer.image { context in
        traits.performAsCurrent {
          UIColor.systemBackground.setFill()
          context.fill(CGRect(origin: .zero, size: bounds.size))
          for fragment in fragments {
            let origin = fragment.layoutFragmentFrame.origin
            fragment.draw(
              at: CGPoint(x: origin.x - bounds.minX, y: origin.y - bounds.minY),
              in: context.cgContext)
          }
        }
      }
    }
  }
#endif
