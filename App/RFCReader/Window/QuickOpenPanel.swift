#if os(macOS)
  import AppKit
  import RFCReaderKit
  import SwiftUI

  /// The window the Go to RFC palette floats in.
  ///
  /// A panel rather than a sheet, because a sheet darkens and blocks the window it is
  /// attached to, and a palette that does that reads as a dialog again. It is a child
  /// of the reader window, so it moves with it, and it goes away the moment it stops
  /// being key — a click back into the reader, or into another app — the way
  /// Spotlight does.
  ///
  /// The frame is fixed at the palette's tallest and the palette hangs from its top
  /// edge, with the rest of the panel transparent. A borderless window that resized
  /// to its content would grow from its bottom-left origin, moving the field up and
  /// down under the reader's eyes as results came and went; a transparent area
  /// passes clicks through to the window below instead.
  final class QuickOpenPanel: NSPanel, NSWindowDelegate {
    private let onClose: () -> Void

    /// Enough for the field and a full list of rows, and the margin the shadow
    /// needs to fall into.
    private static let size = NSSize(width: QuickOpenPalette.width + 2 * margin, height: 460)
    private static let margin: CGFloat = 24
    /// Between the toolbar and the palette's top edge.
    private static let gap: CGFloat = 12

    init(content: some View, onClose: @escaping () -> Void) {
      self.onClose = onClose
      super.init(
        contentRect: NSRect(origin: .zero, size: Self.size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      isOpaque = false
      backgroundColor = .clear
      // Drawn by SwiftUI instead: the window's own shadow follows its alpha as it
      // was when last computed, and the palette changes height with every query.
      hasShadow = false
      isReleasedWhenClosed = false
      delegate = self
      let hosting = NSHostingView(
        rootView:
          content
          .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
          .padding(Self.margin)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      )
      hosting.sizingOptions = []
      contentView = hosting
    }

    /// A borderless window refuses key status by default, and a field in a window
    /// that is never key never takes a keystroke.
    override var canBecomeKey: Bool { true }

    /// Centred on `parent`, hanging just below its toolbar.
    func show(over parent: NSWindow) {
      let contentTop = parent.frame.minY + parent.contentLayoutRect.maxY
      let origin = QuickOpenPlacement.origin(
        of: Self.size,
        over: parent.frame,
        // The margin is transparent, so the panel starts that far above the
        // palette, which sits a little below the toolbar.
        below: contentTop - Self.gap + Self.margin,
        screen: parent.screen?.visibleFrame
      )
      setFrameOrigin(origin)
      parent.addChildWindow(self, ordered: .above)
      makeKeyAndOrderFront(nil)
    }

    /// Esc, whether or not SwiftUI's field saw it first.
    override func cancelOperation(_ sender: Any?) {
      onClose()
    }

    /// ⌘W while the palette is key is addressed to the palette, which has no close
    /// button to answer it with.
    override func performClose(_ sender: Any?) {
      onClose()
    }

    /// File ▸ Close is how ⌘W arrives, and AppKit disables it for a window with no
    /// close button — so without this, `performClose(_:)` is never called.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      menuItem.action == #selector(performClose(_:)) || super.validateMenuItem(menuItem)
    }

    func windowDidResignKey(_ notification: Notification) {
      onClose()
    }

    /// Takes the panel down and, if the keyboard was in it, hands the keyboard back
    /// to the window it came from rather than to whichever window AppKit picks.
    func dismiss() {
      let parent = parent
      let wasKey = isKeyWindow
      parent?.removeChildWindow(self)
      orderOut(nil)
      if wasKey { parent?.makeKey() }
    }
  }
#endif
