import Foundation
import RFCKit

extension NSAttributedString.Key {
    /// The cross reference a run stands for: hit testing, preview, chip drawing.
    public static let rfcReference = NSAttributedString.Key("rfcReference")
    /// Set on heading runs, so the VoiceOver headings rotor can find them.
    public static let rfcAnchor = NSAttributedString.Key("rfcAnchor")
    /// What the layout fragment should draw behind or beside this run.
    public static let rfcDecoration = NSAttributedString.Key("rfcDecoration")
    /// The verbatim block a run came from: the accessibility element needs the
    /// original text, not the laid-out lines. ("Copy Figure" is planned but not
    /// yet implemented; this attribute is what it would read from too.)
    public static let rfcVerbatim = NSAttributedString.Key("rfcVerbatim")
    /// Marks the run that should be drawn as a chip: the span the brackets enclosed.
    public static let rfcChip = NSAttributedString.Key("rfcChip")
    /// The enclosing figure's caption, set on a `.rfcVerbatim` run when the artwork
    /// sits inside a captioned figure: the accessibility element's fallback label
    /// when `Preformatted.name` is absent.
    public static let rfcCaption = NSAttributedString.Key("rfcCaption")
}

public enum RFCDecoration: String, Sendable {
    case blockQuote
    case aside
    case artwork
    case table
}

/// Boxes a `Preformatted` so it can live in an `NSAttributedString` attribute.
public final class VerbatimBox: Sendable {
    public let content: Preformatted
    public init(_ content: Preformatted) { self.content = content }
}

/// Boxes a `CrossReference` for the same reason.
public final class ReferenceBox: Sendable {
    public let reference: CrossReference
    public init(_ reference: CrossReference) { self.reference = reference }
}
