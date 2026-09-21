#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The three-step preamble every TextKit 2 site in the reader needs: reach the
/// backing attributed string, and convert between an `NSTextLocation` and the
/// document-relative character offset the builder's anchors and attribute ranges
/// are expressed in.
///
/// Written out by hand at each call site, this is where the reader's last
/// index-base bug lived — two copies of the same arithmetic disagreeing about
/// what an index was relative to. One spelling, one place to be right, and in the
/// package rather than the App target so a test can call it instead of restating it.
extension NSTextLayoutManager {
    public var attributedText: NSAttributedString? {
        (textContentManager as? NSTextContentStorage)?.attributedString
    }

    /// `location` as a character offset from the start of the document.
    public func offset(of location: any NSTextLocation) -> Int {
        offset(from: documentRange.location, to: location)
    }

    /// The inverse: the location `offset` characters into the document.
    public func location(atOffset offset: Int) -> (any NSTextLocation)? {
        location(documentRange.location, offsetBy: offset)
    }

    /// The document-relative character range of `textRange`, which is what every
    /// `FragmentGeometry` call is expressed in.
    public func range(of textRange: NSTextRange) -> NSRange? {
        let start = offset(of: textRange.location)
        let end = offset(of: textRange.endLocation)
        guard start >= 0, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The same, for an element that knows its own range.
    public func range(of element: NSTextElement) -> NSRange? {
        guard let elementRange = element.elementRange else { return nil }
        return range(of: elementRange)
    }

    /// The text range spanning `range`, in document-relative character offsets.
    public func textRange(for range: NSRange) -> NSTextRange? {
        guard let start = location(atOffset: range.location),
              let end = location(atOffset: NSMaxRange(range)) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
