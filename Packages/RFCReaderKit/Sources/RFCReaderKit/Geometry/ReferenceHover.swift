import CoreGraphics
import Foundation

/// A reference under the pointer: the box that identifies it, and its whole extent,
/// which a preview is anchored to.
public struct HoverTarget: Equatable {
  public let box: ReferenceBox
  public let range: NSRange

  public init(box: ReferenceBox, range: NSRange) {
    self.box = box
    self.range = range
  }

  /// By the box's identity: there is one per reference, so two adjacent references
  /// to the same target are still two hovers.
  public static func == (lhs: HoverTarget, rhs: HoverTarget) -> Bool {
    lhs.box === rhs.box && lhs.range == rhs.range
  }
}

/// The macOS reader's hover, force-click and preview rules, as a value: an event
/// goes in, the state changes, and what the window layer must do comes out.
///
/// The rules are ARCHITECTURE.md's "a reference previews on hover and force click
/// on macOS": a card after a 0.5 s dwell over a reference; a force click previews
/// the document a reference names, or its card; the click that ends a force click
/// never follows the link; following a link previews nothing it lands on until the
/// pointer moves; a mouse-down, a context menu, scrolling or a new document ends
/// whatever is timing or showing. `ReferenceHoverController` owns one of these and
/// does the effects — the timer, the popover, the hit tests — which are AppKit's.
public struct ReferenceHover {
  public enum Dwell: Equatable {
    /// Over a reference: its card, when the dwell ends.
    case card(HoverTarget)
    /// After a scroll: whatever reference the text came to rest under the pointer.
    case restingPointer
  }

  public enum Presentation: Equatable {
    /// A reference's card, which the pointer leaving the reference closes.
    case card
    /// A document preview (#29), which the pointer is meant to travel into.
    case documentPreview
    /// A heading's backlinks (#183), opened by a click on its chip, which the
    /// pointer travels into as it does a document preview: its rows are buttons.
    case backlinks

    /// The pointer leaving the reference, or the text view, on its way there must
    /// not close it, as it does a card.
    var holdsThePointer: Bool { self != .card }
  }

  public enum Event {
    /// The pointer moved to `location`, in screen coordinates, over `target`.
    case pointerMoved(location: CGPoint, target: HoverTarget?)
    /// The pointer left the text view.
    case pointerExited
    /// A mouse-down in the text, with or without Control held.
    case mouseDown(withControl: Bool)
    /// `NSTextView` followed a click on a link, on `reference` if it is one.
    case clickedLink(reference: ReferenceBox?, pointer: CGPoint)
    /// A context menu is opening.
    case contextMenu
    /// The text scrolled.
    case scrolled
    /// A card's dwell ended, with or without a mouse button held.
    case cardDwellElapsed(buttonPressed: Bool)
    /// A scroll's dwell ended, over `target` if the pointer rests on a reference in
    /// the visible text of the active app with no button held.
    case restingDwellElapsed(target: HoverTarget?)
    /// A force click on a reference that previews as a card.
    case forceClickCard(HoverTarget)
    /// A force click on a reference that previews as a document.
    case forceClickDocument(HoverTarget)
    /// The card the last `showCard` asked for is on screen.
    case cardShown
    /// The document preview the last `showDocumentPreview` asked for is on screen.
    case documentPreviewShown
    /// A heading's backlinks are on screen, opened by the click on its chip.
    case backlinksShown
    /// The popover closed by itself: Esc, a click elsewhere, the app going inactive.
    case popoverClosedItself
    /// A click in a document preview, which follows the reference, or on a row of
    /// a heading's backlinks, which goes there; `pointer` is where it was, in
    /// screen coordinates.
    case previewCommitted(pointer: CGPoint)
    /// A new document was installed, or the view is going away.
    case reset
  }

  public enum Effect: Equatable {
    case startDwell(Dwell)
    case cancelDwell
    case closePopover
    case showCard(HoverTarget)
    case showDocumentPreview(HoverTarget)
    /// The mouse-down commits the preview this reader is showing.
    case commitPreview
    /// The click on a link is the tail of a force click, and must not follow it.
    case swallowClick
    /// The click on a link follows it.
    case followLink
  }

  /// A link preview's own reader, whose clicks commit it and which previews nothing.
  public var isPreviewReader: Bool
  /// Whether the pointer coming to rest on a reference previews it. Off while
  /// VoiceOver runs (#514): it moves the pointer onto whatever it reads and scrolls
  /// the text there, and a card that opened for that took VoiceOver's focus away
  /// from the text. A force click still previews.
  public var previewsOnHover = true

  /// The reference the pointer is over, timing or already previewed.
  public private(set) var hovered: ReferenceBox?
  /// The reference a force click just previewed, whose own mouse-up must not
  /// follow it. The next mouse-down starts a click of its own, and forgets it.
  public private(set) var forceClicked: ReferenceBox?
  public private(set) var dwell: Dwell?
  public private(set) var presentation: Presentation?
  /// Where the pointer was, in screen coordinates, when it followed a link. Until it
  /// moves from there, a scroll does not look for a reference under it: the jump the
  /// click caused is not the reader resting on whatever it landed on.
  public private(set) var linkClickPointer: CGPoint?

  public init(isPreviewReader: Bool = false) {
    self.isPreviewReader = isPreviewReader
  }

  /// Whether a move to `pointer`, in screen coordinates, would look at what is
  /// under it. Not in a preview's reader, not while a document preview or a
  /// heading's backlinks are up, and not while the pointer is still where it
  /// followed a link: `handle` drops the target of such a move, so the controller
  /// skips the hit test, which is a TextKit layout query on every mouse move.
  public func wantsTarget(at pointer: CGPoint) -> Bool {
    guard !isPreviewReader, presentation?.holdsThePointer != true else { return false }
    return pointer != linkClickPointer
  }

  public mutating func handle(_ event: Event) -> [Effect] {
    switch event {
    case .pointerMoved(let pointer, let target):
      // Compared, not just cleared: a move event is not proof the pointer moved.
      if let linkClickPointer {
        guard pointer != linkClickPointer else { return [] }
        self.linkClickPointer = nil
      }
      return hover(over: target)

    case .pointerExited:
      // The pointer leaves the text view on its way into a document preview.
      guard presentation?.holdsThePointer != true else { return [] }
      return cancel()

    case .mouseDown(let withControl):
      // A dwell still timing belongs to the pointer before the click: a drag that
      // began on a reference would otherwise open its card wherever it ended.
      var effects = cancel()
      // A control-click is the context menu, in a preview as anywhere else.
      if isPreviewReader, !withControl { effects.append(.commitPreview) }
      return effects

    case .clickedLink(let box, let pointer):
      // Swallowed once, when it is the reference the force click previewed.
      if let forceClicked, box === forceClicked {
        self.forceClicked = nil
        return [.swallowClick]
      }
      // Following a reference is what the preview was for; one still timing would
      // otherwise open over the document the click is leaving.
      var effects = cancel()
      linkClickPointer = pointer
      effects.append(.followLink)
      return effects

    case .contextMenu:
      // A card would open under the menu, or the moment it closes.
      return cancel()

    case .scrolled:
      // The popover is anchored to text the scroll moved. Then a dwell, restarted
      // by every tick, so the resting pointer is hit-tested once scrolling stops
      // rather than per frame of a fling. Not for the scroll a link caused.
      var effects = cancel()
      guard previewsOnHover, linkClickPointer == nil else { return effects }
      dwell = .restingPointer
      effects.append(.startDwell(.restingPointer))
      return effects

    case .cardDwellElapsed(let buttonPressed):
      guard case .card(let target) = dwell else { return [] }
      dwell = nil
      // A button still held is a click or a drag in progress, not a dwell.
      guard !buttonPressed, hovered === target.box else { return [] }
      return [.showCard(target)]

    case .restingDwellElapsed(let target):
      guard dwell == .restingPointer else { return [] }
      dwell = nil
      guard !isPreviewReader, let target else { return [] }
      hovered = target.box
      return [.showCard(target)]

    case .forceClickCard(let target):
      guard !isPreviewReader else { return [] }
      // Already showing from a hover: the force click adds nothing.
      if hovered === target.box, presentation == .card {
        forceClicked = target.box
        return []
      }
      var effects = cancel()
      hovered = target.box
      forceClicked = target.box
      effects.append(.showCard(target))
      return effects

    case .forceClickDocument(let target):
      guard !isPreviewReader else { return [] }
      // Already open from this force click: the stage-2 pressure step and a
      // `quickLook(with:)` can both arrive for one force click.
      if forceClicked === target.box, presentation == .documentPreview { return [] }
      // Over a hover card too: this is the bigger answer to the same question.
      // Presenting only once it is on screen, as a card is: one that never appears
      // must not leave the pointer's moves and exits suppressed for it.
      var effects = cancel()
      hovered = target.box
      forceClicked = target.box
      effects.append(.showDocumentPreview(target))
      return effects

    case .cardShown:
      presentation = .card
      return []

    case .documentPreviewShown:
      presentation = .documentPreview
      return []

    case .backlinksShown:
      presentation = .backlinks
      return []

    case .popoverClosedItself:
      // The hover it belonged to is over too, or the same reference could not
      // preview again until the pointer left it.
      presentation = nil
      hovered = nil
      forceClicked = nil
      return []

    case .previewCommitted(let pointer):
      // The popover closes as the reader moves, not before it; and the scroll the
      // commit causes must not preview whatever lands under the pointer.
      let effects = cancel()
      linkClickPointer = pointer
      return effects

    case .reset:
      return cancel()
    }
  }

  private mutating func hover(over target: HoverTarget?) -> [Effect] {
    // A preview previews nothing itself; and a document preview is to be read, and
    // backlinks chosen from, so the pointer leaving on its way there must not close
    // them.
    guard !isPreviewReader, presentation?.holdsThePointer != true else { return [] }
    guard let target else { return cancel() }
    guard target.box !== hovered else { return [] }
    var effects = cancel()
    guard previewsOnHover else { return effects }
    hovered = target.box
    dwell = .card(target)
    effects.append(.startDwell(.card(target)))
    return effects
  }

  /// Ends the dwell and the popover, if either is active, and forgets a force
  /// click's pending mouse-up.
  private mutating func cancel() -> [Effect] {
    var effects: [Effect] = []
    if dwell != nil { effects.append(.cancelDwell) }
    if presentation != nil { effects.append(.closePopover) }
    dwell = nil
    hovered = nil
    forceClicked = nil
    presentation = nil
    return effects
  }
}
