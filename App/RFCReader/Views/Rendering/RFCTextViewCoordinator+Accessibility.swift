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
/// rotors — headings, links, diagrams — restore jump navigation. Which runs are
/// stops, and which stop comes next, is `AccessibleReading.Rotors` and
/// `AccessibleReading.nextRotorItem`, in RFCReaderKit, where they are tested; this
/// only hands them to each platform's rotor API.
extension RFCTextViewCoordinator {
  typealias AccessibilityRotorItem = AccessibleReading.RotorItem

  /// Called once from `install(_:)`, the only place the storage changes — the
  /// cache is invalidated by the next `install` overwriting it, not by anything
  /// rotor-search-triggered.
  func deriveAccessibilityItems() {
    let rotors = built.map { AccessibleReading.Rotors($0.text) } ?? .empty
    accessibilityHeadings = rotors.headings
    accessibilityLinks = rotors.links
    accessibilityDiagrams = rotors.diagrams
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
        self?.accessibilityRotorResult(
          items: self?.accessibilityHeadings ?? [], predicate: predicate)
      }
      let links = UIAccessibilityCustomRotor(systemType: .link) { [weak self] predicate in
        self?.accessibilityRotorResult(items: self?.accessibilityLinks ?? [], predicate: predicate)
      }
      let diagrams = UIAccessibilityCustomRotor(systemType: .image) { [weak self] predicate in
        self?.accessibilityRotorResult(
          items: self?.accessibilityDiagrams ?? [], predicate: predicate)
      }
      textView.accessibilityCustomRotors = [headings, links, diagrams]
    }

    /// `UIAccessibilityCustomRotorItemResult` has no label override (unlike its
    /// AppKit counterpart's `customLabel`), so on iOS a diagram rotor stop is
    /// announced from whatever VoiceOver already reads at `targetRange` — real
    /// navigation to the diagram, but not a spoken name.
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
      guard
        let item = AccessibleReading.nextRotorItem(
          in: items, after: currentOffset, forward: predicate.searchDirection == .next),
        let start = textView.position(
          from: textView.beginningOfDocument, offset: item.range.location),
        let end = textView.position(from: start, offset: item.range.length),
        let range = textView.textRange(from: start, to: end)
      else { return nil }
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
    // conformance (the `@MainActor` before the protocol name below). Approachable
    // concurrency would infer it; it is spelled out because it is a claim about
    // AppKit, not a default. `NSAccessibility` bridge methods are a
    // main-thread-only contract in practice, just not one the compiler can see,
    // so this asserts what every other AppKit accessibility override here already
    // assumes.
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
      guard
        let item = AccessibleReading.nextRotorItem(
          in: items,
          after: currentLocation,
          forward: searchParameters.searchDirection == .next
        )
      else { return nil }
      let result = NSAccessibilityCustomRotor.ItemResult(targetElement: textView)
      result.targetRange = item.range
      result.customLabel = item.label
      return result
    }
  }
#endif
