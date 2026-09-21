#if canImport(UIKit)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformFontDescriptor = UIFontDescriptor
#else
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformFontDescriptor = NSFontDescriptor
#endif

/// Dynamic colours, stored in the attributed string unresolved so that a change of
/// appearance or accent costs a redraw rather than a rebuild of the whole document.
public enum RFCColors {
    public static var label: PlatformColor {
        #if canImport(UIKit)
        .label
        #else
        .labelColor
        #endif
    }

    public static var secondaryLabel: PlatformColor {
        #if canImport(UIKit)
        .secondaryLabel
        #else
        .secondaryLabelColor
        #endif
    }

    public static var accent: PlatformColor {
        #if canImport(UIKit)
        .tintColor
        #else
        .controlAccentColor
        #endif
    }

    public static var quaternaryFill: PlatformColor {
        #if canImport(UIKit)
        .quaternarySystemFill
        #else
        .quaternaryLabelColor
        #endif
    }
}

/// Symbolic traits, which AppKit and UIKit spell differently.
public enum RFCTraits {
    public static var italic: PlatformFontDescriptor.SymbolicTraits {
        #if canImport(UIKit)
        .traitItalic
        #else
        .italic
        #endif
    }

    public static var bold: PlatformFontDescriptor.SymbolicTraits {
        #if canImport(UIKit)
        .traitBold
        #else
        .bold
        #endif
    }
}
