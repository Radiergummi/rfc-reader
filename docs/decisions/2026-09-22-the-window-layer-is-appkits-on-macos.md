# The window layer is AppKit's on macOS

*Decided 22 September 2026, after four earlier attempts recorded in issue #34 and two more measured in `docs/decisions/2026-09-22-window-hijack-probe-results.md`.*

The contents panel must sit in the window the way Pages' inspector does: full-height glass, the **window tab bar** ending at the panel's leading edge rather than running under it, and the toolbar splitting at the same point.
None of that is reachable from SwiftUI, because window chrome only engages for an `NSSplitViewController` that **is** the window's `contentViewController`.
`.inspector` is not a split item at all — probed on the running app, the controller still reports three items with it showing — and an item added to SwiftUI's own controller is reconciled away.

Replacing a `WindowGroup` window's `contentViewController` looked like the cheap way in, and it is not: SwiftUI treats the scene as closed and opens a replacement window, which the installer replaces in turn — **24 windows in 0.9 s**, measured, with the scene's view tree parked, hidden, visible and spike-shaped.
So macOS has no `WindowGroup`.
`AppDelegate` makes every window; each is a `ReaderWindowController` holding a four-item split controller — sidebar, list, reader, inspector — with the existing SwiftUI views in `NSHostingController`s.

What this costs and what it does not: the menu bar is still SwiftUI's, because a `Settings`-only scene honors `.commands` (measured: the full `File`/`Edit`/`View`/`Window`/`Help` bar, with our own items in it). What `WindowGroup` used to contribute and we now write ourselves is New Window, New Tab, and the per-window state that `ContentView` held as `@State`. `@FocusedValue` does **not** survive: published from a hosted root it never resolves, and ⌘L opened nothing at all until the commands were pointed at the key window through `ActiveReaderWindow`.

The toolbar has a tracking separator on **all three dividers**, which is what gives each item a column to belong to: the sidebar's toggle over the sidebar, the title over the list it names, Back and Forward at the leading edge of the reader they act on, the document's actions at the reader's trailing edge, and the panel's toggle out on the panel's glass.

**The title and subtitle are a toolbar item of our own** (`titleVisibility = .hidden`), declared after Back and Forward.
A window that draws its own title puts it in a block at the start of the document's toolbar section, and that block expands to fill — measured, it pushed Back and Forward from 204 pt out to 1199 on a 1500 pt window, with and without a subtitle.
Two other ways out were built and rejected: the expanded toolbar style gives the title its own row and costs a second row of titlebar, with the sidebar's toggle dropping onto the sidebar's search field; a leading `NSTitlebarAccessoryViewController` is laid out over the sidebar and pushes the sidebar's toggle into the overflow menu.
An ordinary item sits where it is declared and takes the width it needs.
Like every custom view in a toolbar it must carry its own constraints — an intrinsic width alone left the title drawn on top of the navigation group — and it is `isBordered = false`, or the toolbar draws it as a button.

Three pieces of arithmetic are load-bearing, and each was got wrong first:

- **The window must not grow when the panel opens.** AppKit adds an uncollapsed inspector's thickness on top of `contentMinSize`, so a fixed 900 pt floor became 1222 and the window grew to meet it. The floor drops by the panel's width while the panel shows, which keeps the effective minimum constant.
- **The reader keeps its full width underneath, and two separate layers have to be told so.** The panel's width comes back as a right safe-area inset, and it does damage twice over. *In SwiftUI:* the width `DocumentView` derives its column from is read by a `GeometryReader` in the reader's hosted root, and a root that honors the inset reports 919 pt with the panel shut and 599 pt with it open — so `NSHostingController.safeAreaRegions = []` on that root is load-bearing, and holds it at 919 both ways with the view's own frame unchanged and the inset still arriving. *In AppKit:* a scroll view turns the same inset into content insets that the text view tracks — the scroll view stayed 1019 pt while the text view went to 699 and its column from 712 to 392 — and `safeAreaRegions` does not reach the clip view, nor does `ignoresSafeArea` from any level above it. `ReaderScrollView` refuses the trailing inset there, and only the trailing one: zeroing the insets outright puts the first lines of the document behind the toolbar. Neither fix substitutes for the other; removing either one re-wraps the document when the panel opens.
- **A hosted view must not size the window.** A hosting controller reports its content's preferred size, and as a split item that reaches the window: it pinned the window at 219 pt tall. `sizingOptions = []` on every hosted root.

**The panel follows the document, and a new tab will try not to.**
A window ordered into a tab group adopts the group's inspector state, which left an empty strip of glass over a tab that had nothing open in it.
Measured on this build: `isCollapsed` is still the one the controller set immediately after `addTabbedWindow(_:ordered:)`, and the sibling's immediately after the window is ordered front — so the adoption happens inside `makeKeyAndOrderFront(_:)`, and a tab opened in the background, which is never made key, never inherits at all.
A correction made once the ordering call has returned holds, unchanged on the next turn of the run loop and a second later.
`AppDelegate` makes it there, at the one place that creates a tab; everywhere else the rule is the document's own, observed on `ReaderState.canDescribe`.
Enforcing it on `windowDidBecomeKey` instead works but is a recurring answer to a question only asked at creation.

The toolbar's items are AppKit's own.
Hosted SwiftUI controls were tried first, to keep the declarations `DocumentView` already had, and an `NSHostingView` reports no width the toolbar will honor: every item drew on top of the one before it, the bookmark inside the back/forward group and the share icon over the panel's toggle.

Verified by measurement rather than by eye, on RFC 9110 in a 1500 pt window with a 320 pt panel: the tab bar ends at 1177 pt against a panel edge of 1180; window and reader unchanged at 1500 and 1019 across a toggle; column 712 both ways; **zero differing pixels** in the region the panel does not cover.
Captures that disagreed with that turned out to be racing the reading-position restore — settle the document before diffing.

## Re-test on each macOS major

The decision stands only as long as SwiftUI can't reach the window's chrome.
What it costs is everything `WindowGroup` gives for free: state restoration, `@FocusedValue`, `.searchable`, focus between columns, Edit ▸ Find and `openWindow(value:)`.
So on each new macOS major, the spike is built again, time-boxed to a day, and measured against the criteria the decision was taken on (#142).

**The spike:** a standalone app with a `WindowGroup(for: RFCLink.self)` whose root is a three-column `NavigationSplitView` (sidebar, list, a text view under a `GeometryReader`), and an `.inspector` on the detail column.
`WindowGroup(for:)` needs a `Codable` value, which `RFCLink` is not, so the spike declares the conformance itself.
It is built with the new SDK and run on the new release.

**What it must do, all of it,** for the window layer to go back to SwiftUI:

1. The inspector is drawn as full-height glass, as Pages' is.
2. Each column owns its titlebar section, and the toolbar splits at each divider.
3. The window's tab bar ends at the inspector's leading edge, rather than running under it.
4. Opening the inspector changes neither the window's width nor the width the detail column's `GeometryReader` reports. It must be the same number shut and open, or the reader re-wraps and loses its place.
5. The split view controller AppKit sees is the window's `contentViewController`, with the inspector as a real `NSSplitViewItem` (probed on the running app).
6. It opens a window at launch. On macOS 26 `WindowGroup(for:)` left the app running with no interface at all (`2026-09-22-per-tab-navigation-and-how-a-tab-gets-opened.md`); a spike that shows no window has measured none of the above, and is recorded as failing this one.

Any one missing keeps the window AppKit's.
Record each run below, dated, with the release, the build and what each criterion measured.

**Runs**

- **macOS 26, 22 September 2026:** the decision's own measurements, above and in `2026-09-22-window-hijack-probe-results.md`. `.inspector` isn't a split item (the controller reports three items with it showing), so 1, 2, 3 and 5 fail, and an item added to SwiftUI's controller is reconciled away. `WindowGroup(for:)` opened no window at launch, so 6 fails too. Stays AppKit's.
- **macOS 27:** not yet run.

