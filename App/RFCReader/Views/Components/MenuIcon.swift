import RFCReaderKit
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension DocumentMenus.Icon {
  #if os(macOS)
    /// The symbol as a menu item's image. A menu draws a template image in its own
    /// color, so an icon with a color of its own is made a palette image, which the
    /// menu leaves as it is.
    var image: NSImage? {
      let symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      guard let color else { return symbol }
      return symbol?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(paletteColors: [NSColor(color.color)]))
    }
  #else
    /// The symbol as a menu item's image. A menu tints a template image, so an icon
    /// with a color of its own is drawn in it, always.
    var image: UIImage? {
      let symbol = UIImage(systemName: symbol)
      guard let color else { return symbol }
      return symbol?.withTintColor(UIColor(color.color), renderingMode: .alwaysOriginal)
    }
  #endif

  /// The same, for a SwiftUI menu's label.
  var label: Image? {
    #if os(macOS)
      image.map { Image(nsImage: $0) }
    #else
      image.map { Image(uiImage: $0) }
    #endif
  }
}

#if os(macOS)
  extension NSMenuItem {
    /// Keeps the item's image where macOS 27 would hide it, as it hides every menu
    /// icon an item does not ask to keep. Behind the compiler check too, because the
    /// property is in the macOS 27 SDK only and CI builds with Xcode 26's.
    func showsImageOnMacOS27() {
      #if compiler(>=6.4)
        if #available(macOS 27, *) { preferredImageVisibility = .visible }
      #endif
    }
  }
#endif
