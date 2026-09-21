import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// VoiceOver navigation for the single-text-view reader body.
///
/// Collapsing every block into one `NSTextContentStorage` collapsed VoiceOver
/// navigation with it: before this milestone each block was its own accessibility
/// element and VoiceOver could move between them, but a plain text view is one
/// element, navigable only character by character or line by line. Three custom
/// rotors — headings, links, diagrams — restore jump navigation, built straight
/// from the attributes `DocumentTextBuilder` already tags runs with.
///
/// `.rfcAnchor` is set on heading runs only (not every anchor `AnchorIndex` carries
/// — that index also covers figures, tables and reference rows, which would make
/// the headings rotor list hundreds of non-headings), so enumerating it directly
/// over the storage is both the correct filter and the only way to get a text
/// *range* per heading, which the index's bare offsets do not carry.
extension RFCTextViewCoordinator {
    /// One rotor stop: the run's extent, and — for diagrams only — what VoiceOver
    /// should say about it. Headings and links keep `label` nil and let VoiceOver
    /// read the actual text at `range`, which already says the right thing.
    struct AccessibilityRotorItem {
        let range: NSRange
        let label: String?
    }

    /// Enumerates `.rfcAnchor`, `.link` and `.rfcVerbatim` once and caches the
    /// result, so a rotor search is a lookup in a small cached array rather than a
    /// fresh walk of the whole document. Called once from `install(_:)`, the only
    /// place the storage changes — the cache is invalidated by the next `install`
    /// overwriting it, not by anything rotor-search-triggered.
    func deriveAccessibilityItems() {
        guard let text = built?.text else {
            accessibilityHeadings = []
            accessibilityLinks = []
            accessibilityDiagrams = []
            return
        }
        let full = NSRange(location: 0, length: text.length)

        // Both rotors are the same walk: every run carrying the attribute, labelled
        // by the text under it.
        func items(carrying key: NSAttributedString.Key) -> [AccessibilityRotorItem] {
            var items: [AccessibilityRotorItem] = []
            text.enumerateAttribute(key, in: full) { value, range, _ in
                guard value != nil else { return }
                items.append(AccessibilityRotorItem(range: range, label: nil))
            }
            return items
        }
        accessibilityHeadings = items(carrying: .rfcAnchor)
        accessibilityLinks = items(carrying: .link)

        // Adjacent runs sharing the same `VerbatimBox` instance are one diagram —
        // `appendVerbatim` emits a source-code language label and its body as two
        // back-to-back runs over the same box. Coalescing by reference identity
        // keeps that pair, and a multi-line artwork's many line fragments, as one
        // rotor stop rather than one per run.
        var diagrams: [AccessibilityRotorItem] = []
        var openBox: ObjectIdentifier?
        text.enumerateAttribute(.rfcVerbatim, in: full) { value, range, _ in
            guard let box = value as? VerbatimBox else {
                openBox = nil
                return
            }
            let identity = ObjectIdentifier(box)
            if identity == openBox, let last = diagrams.popLast() {
                diagrams.append(AccessibilityRotorItem(range: NSUnionRange(last.range, range), label: last.label))
            } else {
                let caption = text.attribute(.rfcCaption, at: range.location, effectiveRange: nil) as? String
                diagrams.append(AccessibilityRotorItem(range: range, label: box.content.name ?? caption ?? "Diagram"))
            }
            openBox = identity
        }
        accessibilityDiagrams = diagrams
    }

    /// The next (or previous) item strictly after (or before) `location`, or the
    /// first/last item when there is no current position — matching both
    /// platforms' "nil current item means start from the end the direction
    /// implies" contract. Returns nil at either end of the list, which both
    /// platforms treat as "no further item" and VoiceOver marks with a boundary
    /// sound rather than repeating the last item.
    static func nextAccessibilityItem(
        in items: [AccessibilityRotorItem],
        after location: Int?,
        forward: Bool
    ) -> AccessibilityRotorItem? {
        guard !items.isEmpty else { return nil }
        guard let location, location != NSNotFound else { return forward ? items.first : items.last }
        return forward
            ? items.first { $0.range.location > location }
            : items.last { $0.range.location < location }
    }
}

#if canImport(UIKit)
extension RFCTextViewCoordinator {
    /// Builds the three rotors once, the moment the text view exists. Each
    /// closure captures `self` weakly and reads the cached item arrays fresh on
    /// every search, so document swaps need no rotor rebuild — only
    /// `deriveAccessibilityItems()` needs to re-run, which `install(_:)` does.
    func setUpAccessibilityRotors() {
        guard let textView else { return }
        let headings = UIAccessibilityCustomRotor(systemType: .heading) { [weak self] predicate in
            self?.accessibilityRotorResult(items: self?.accessibilityHeadings ?? [], predicate: predicate)
        }
        let links = UIAccessibilityCustomRotor(systemType: .link) { [weak self] predicate in
            self?.accessibilityRotorResult(items: self?.accessibilityLinks ?? [], predicate: predicate)
        }
        let diagrams = UIAccessibilityCustomRotor(systemType: .image) { [weak self] predicate in
            self?.accessibilityRotorResult(items: self?.accessibilityDiagrams ?? [], predicate: predicate)
        }
        textView.accessibilityCustomRotors = [headings, links, diagrams]
    }

    /// `UIAccessibilityCustomRotorItemResult` has no label override (unlike its
    /// AppKit counterpart's `customLabel`), so on iOS a diagram rotor stop is
    /// announced from whatever VoiceOver already reads at `targetRange` — real
    /// navigation to the diagram, but not a spoken name. See the task report.
    private func accessibilityRotorResult(
        items: [AccessibilityRotorItem],
        predicate: UIAccessibilityCustomRotorSearchPredicate
    ) -> UIAccessibilityCustomRotorItemResult? {
        guard let textView else { return nil }
        // `currentItem` is audited non-optional in the header, but the doc comment
        // is explicit that it is nil to start a search — and, being a class
        // reference, a null pointer received into it still reads as nil once
        // rebound to an optional here, so this is the safe way to check it.
        let current: UIAccessibilityCustomRotorItemResult? = predicate.currentItem
        var currentOffset: Int?
        if let range = current?.targetRange {
            currentOffset = textView.offset(from: textView.beginningOfDocument, to: range.start)
        }
        guard let item = Self.nextAccessibilityItem(in: items, after: currentOffset, forward: predicate.searchDirection == .next),
              let start = textView.position(from: textView.beginningOfDocument, offset: item.range.location),
              let end = textView.position(from: start, offset: item.range.length),
              let range = textView.textRange(from: start, to: end) else { return nil }
        return UIAccessibilityCustomRotorItemResult(targetElement: textView, targetRange: range)
    }
}
#else
extension RFCTextViewCoordinator {
    /// Same shape as the UIKit half: three rotors, built once and set directly on
    /// the `NSTextView` VoiceOver focuses — not the coordinator, not the
    /// enclosing `NSScrollView` — so the item search delegate below is reachable
    /// the moment VoiceOver asks the text view for its custom rotors.
    func setUpAccessibilityRotors() {
        guard let textView else { return }
        let headings = NSAccessibilityCustomRotor(rotorType: .heading, itemSearchDelegate: self)
        let links = NSAccessibilityCustomRotor(rotorType: .link, itemSearchDelegate: self)
        let diagrams = NSAccessibilityCustomRotor(rotorType: .image, itemSearchDelegate: self)
        textView.setAccessibilityCustomRotors([headings, links, diagrams])
    }
}

extension RFCTextViewCoordinator: @MainActor NSAccessibilityCustomRotorItemSearchDelegate {
    // `NSAccessibilityCustomRotorItemSearchDelegate` is not itself `@MainActor` —
    // unlike UIKit's rotor search block, it carries no `NS_SWIFT_UI_ACTOR`
    // annotation — so conforming from a `@MainActor` type needs an isolated
    // conformance (the `@MainActor` before the protocol name below) rather than
    // plain conformance, which Swift 6 strict concurrency rejects as crossing
    // into actor-isolated code unsafely. AppKit's `NSAccessibility` bridge methods
    // are a main-thread-only contract in practice, just not one the compiler can
    // see, so this asserts what every other AppKit accessibility override here
    // already assumes.
    @objc func rotor(
        _ rotor: NSAccessibilityCustomRotor,
        resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters
    ) -> NSAccessibilityCustomRotor.ItemResult? {
        guard let textView else { return nil }
        let items: [AccessibilityRotorItem]
        switch rotor.type {
        case .heading: items = accessibilityHeadings
        case .link: items = accessibilityLinks
        case .image: items = accessibilityDiagrams
        default: return nil
        }
        let currentLocation = searchParameters.currentItem?.targetRange.location
        guard let item = Self.nextAccessibilityItem(
            in: items,
            after: currentLocation,
            forward: searchParameters.searchDirection == .next
        ) else { return nil }
        let result = NSAccessibilityCustomRotor.ItemResult(targetElement: textView)
        result.targetRange = item.range
        result.customLabel = item.label
        return result
    }
}
#endif
