# A reference previews on hover and force click on macOS, and on long press on iOS

*Decided September 2026 (issues #28, #29).*
`ReferencePreview` is presented by a 0.5 s hover dwell on macOS — an `NSTrackingArea`, then an `NSPopover` anchored to the reference's whole extent — and by `textView(_:menuConfigurationFor:defaultMenu:)` on iOS, with the default menu alongside.
Both look the reference up with `NSAttributedString.reference(at:)` in `RFCReaderKit`, which takes the attribute's `longestEffectiveRange`: a chip is three storage runs, so the storage run is a third of it.
A force click on a reference is the "preview on hard press" of VISION.md's Tier 1, and since #29 it previews the way Safari previews a link: the document the reference names, readable and scrollable, at the place it names — `DocumentPreview`, a second `RFCTextView` with its own storage, built by `DocumentTextBuilder` at the popover's width, in an `NSPopover` beside the reference.
The reader's own body stays one storage.
Links inside the preview are inert, it previews nothing itself, and a click anywhere in it is the commit: the reader follows the reference as a click on it would have, modifiers included, and the popover closes.
What a reference previews is `LinkPreview` in `RFCReaderKit`; a bibliography entry that names no RFC has nothing of ours to show and keeps the card.
On iOS a long press shows the same `DocumentPreview` as the context menu's preview view, sized with `LinkPreview.documentSize(fitting:)` against the window so the menu still fits under it, with the default menu beside it.
A context menu's preview takes no touches: a tap on it performs the text item's primary action, which follows the reference.
That action is returned as a `UIAction`, never performed inside `primaryActionFor`: UIKit asks for the primary action as a long press begins, and following the link there is what made a long press navigate (#29).
Both are to be confirmed on a device (#431).
The gesture is caught inside the click.
On Force Touch hardware a force click on a link reaches neither `quickLook(with:)` nor `pressureChange(with:)`: logged on a trackpad (#29), `NSTextView.mouseDown`'s own tracking loop takes the click's pressure events off the queue and handles stage 2 itself — that is how Look Up appears on a word — and for our links it shows nothing.
So `ReaderTextView` tracks a mouse-down that lands on a reference itself.
The first pressure event of stage 2 previews the reference or, on a reference with no preview, hands the event to `NSTextView`'s own `quickLook(with:)` for Look Up; either way the click's mouse-up is swallowed, so a force click never follows the link.
Look Up from inside the tracking loop is not yet checked on Force Touch hardware; if it does not appear, the fallback is a force click that does nothing there.
It is detected by `stage`, not by `stageTransition`, which measures the way to the next stage and reads 0 on the first event of stage 2.
A plain release follows the link through `clicked(onLink:at:)`, modifiers included, as `NSTextView` would have; a drag hands the mouse-down back to `NSTextView`, which drags the link as it always did.
A mouse-down anywhere else is `NSTextView`'s, so Look Up keeps working on every other word, and `quickLook(with:)` still takes Look Up from the menu or the keyboard on a reference.
The link click that ends a force click on a reference is swallowed once, for a force click AppKit does route through `quickLook(with:)`; matching `eventNumber` instead was tried and is a crash: it raises on any event that is not a mouse event, which Look Up from a gesture or the keyboard is.
A commit closes the popover as the reader moves, not before it.
A place in the same document scrolls there with the reader's own animated jump.
Another document cross-fades in over 100 ms (`RFCTextViewCoordinator.documentCrossFade`, an opacity transition on `ReaderHost`'s `DocumentView` that only an animated change triggers); every other open still cuts.
A control-click in the preview is its context menu, not a commit.
The preview's reader has no header, and a hosted `EmptyView` measured with an unbounded height answers with that height, 1.8e308: as an inset it made the text view's frame NaN, which AppKit traps on, so a header that answers with the height it was offered counts as no header (`ReaderLayout.headerHeight`).
A mouse-down, a context menu or a new document cancels a dwell in progress, and a dwell that ends with a button held is a click or a drag, not a hover, so it shows nothing: otherwise a drag that began on a reference would open its card wherever it ended.
A force click on a reference that has no card is Look Up's, like any other word.
Scrolling closes the card and, once it has stopped for the dwell, hit-tests under the resting pointer — once, not per scroll tick.
The scroll that following a link causes does not: until the pointer moves from where it clicked, nothing it lands on previews.
A card that closes itself (Esc, a click elsewhere, the app going inactive) ends its hover through the popover's delegate, so the same reference can preview again without the pointer leaving it first, and Look Up carrying another window's event, a menu's, is left to Look Up.
The tracking area is `.activeInActiveApp`, not `.activeInKeyWindow`: a popover's window can become key (`_NSPopoverWindow.canBecomeKey` is true), and with it the moves and the exit that close the card would stop.
A reference to another document shows its title, status and abstract; one within the document shows its section's heading, which the builder records on the section's `AnchorIndex` entry — the heading is what makes an entry a section, so the two cannot disagree — and one to a figure or a table shows nothing, having nothing to add to its own words.
While VoiceOver runs, nothing previews on hover, after a pointer move or a scroll alike (#514): VoiceOver moves the pointer onto whatever it reads and scrolls the text there, and the card that opened for it took VoiceOver's focus into the popover at every citation.
A force click still previews.

These rules are `ReferenceHover` in `RFCReaderKit`, a value that takes an event — a move, an exit, a mouse-down, a link click, a scroll, a dwell ending, a force click, a popover closing itself, a commit, a new document — and returns what the window layer must do, and `ReferenceHoverTests` pins each of them.
They were six mutable fields of the coordinator, which no test could reach.
`ReferenceHoverController` in the App owns the value and does its effects AppKit's way: the tracking area, the popover and its delegate, and the dwell, a cancellable `Task.sleep`.
The coordinator keeps only what needs the document: the hit test, and what a reference previews as.

The hover tracking existed from the start and never fired, which is worth knowing about AppKit: a tracking area sends its owner `mouseMoved:`, and on a class that is not an `NSResponder` Swift names `@objc func mouseMoved(with:)` `mouseMovedWith:`.
AppKit skips an owner that does not respond, so the area was installed and nothing arrived.
Spell the selector out, `@objc(mouseMoved:)`.
The raw `rfc://` tooltip that appeared instead is `NSTextView.displaysLinkToolTips`, on by default, which the reader turns off.
An external link's destination is still worth reading before it is followed, so `DocumentTextBuilder` gives an external link an explicit `.toolTip` of its URL, and a reference none.
That is correct by construction rather than by a delegate filtering what AppKit proposes.
It is also observed working: in a TextKit 2 `NSTextView` with `displaysLinkToolTips` off, a mouse move over a `.toolTip` run reaches `textView(_:willDisplayToolTip:forCharacterAt:)` with that tooltip, and one over a link reaches nothing; with it on, the link proposes its URL through the same call.
