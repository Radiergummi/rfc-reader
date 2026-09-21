#if canImport(UIKit)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformFontDescriptor = UIFontDescriptor
public typealias PlatformImage = UIImage
#else
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformFontDescriptor = NSFontDescriptor
public typealias PlatformImage = NSImage

extension NSImage {
    /// Mirrors `UIImage(systemName:)` so the builder can ask for an SF Symbol
    /// without branching on platform.
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }
}
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

extension PlatformImage {
    /// An SF Symbol rendered at `pointSize`. AppKit and UIKit spell the
    /// configuration step differently (`withSymbolConfiguration` against
    /// `withConfiguration`); that difference belongs here rather than in the builder.
    static func symbol(named name: String, pointSize: CGFloat) -> PlatformImage? {
        let configuration = SymbolConfiguration(pointSize: pointSize, weight: .regular)
        #if canImport(UIKit)
        return PlatformImage(systemName: name)?.withConfiguration(configuration)
        #else
        return PlatformImage(systemName: name)?.withSymbolConfiguration(configuration)
        #endif
    }
}

extension PlatformFont {
    /// This font with `traits` added, or this font unchanged when the descriptor
    /// cannot supply them. UIKit's `withSymbolicTraits` returns an optional
    /// descriptor and AppKit's does not, and only AppKit's font initializer is
    /// failable; both spellings collapse to the same fallback here.
    func adding(traits: PlatformFontDescriptor.SymbolicTraits) -> PlatformFont {
        let descriptor = fontDescriptor
        let combined = descriptor.symbolicTraits.union(traits)
        #if canImport(UIKit)
        guard let traited = descriptor.withSymbolicTraits(combined) else { return self }
        return PlatformFont(descriptor: traited, size: pointSize)
        #else
        return PlatformFont(descriptor: descriptor.withSymbolicTraits(combined), size: pointSize) ?? self
        #endif
    }
}
