# AppKit window layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the macOS reader an AppKit-owned window layer so the window tab bar and the toolbar are confined by the contents panel, without the reader's text moving, re-wrapping, or losing its scroll position when the panel opens.

**Architecture:** On macOS the app has no `WindowGroup`: an `NSApplicationDelegate` creates every window, each an `NSWindowController` whose `contentViewController` is an `NSSplitViewController` — sidebar, list, reader, inspector — with each item hosting the existing SwiftUI view in an `NSHostingController`, and an `NSToolbar` owned by our delegate carrying an `NSTrackingSeparatorToolbarItem`. The panel is a real split item, so AppKit confines the tab bar and splits the toolbar itself. The menu bar is still SwiftUI's: a `Settings`-only scene keeps `.commands` working (measured, M7), so only window creation moves to AppKit. The reader item extends underneath the panel and ignores the resulting safe-area inset inside the representable. iOS is untouched.

**Completed 2026-09-22.** All seven tasks are landed on `appkit-window-layer`; the outcome and final numbers are in the spec's "Round three". Two things the plan got wrong and the work corrected: Task 4's fix belongs in an `NSScrollView` subclass rather than in `makeNSView`'s insets (M9), and Task 3's `DocumentOutline` became `ReaderState`, which also carries the Original Text toggle, because the toolbar left `DocumentView` in Task 2 and took that state with it.

**Revised 2026-09-22 after M6:** this plan first tried to keep `WindowGroup` and replace the window's content view controller. Measured in the real app, SwiftUI destroys and re-opens any window whose content it loses — 24 windows in 0.9 s. The window has to be ours from birth. Tasks 2, 3, 4, 6 and 7 are unaffected; Task 1 and Task 5 are rewritten.

**Tech Stack:** Swift 6 (complete strict concurrency), SwiftUI, AppKit (`NSSplitViewController`, `NSToolbar`, `NSHostingController`), SwiftData, Observation.

**Spec:** `docs/superpowers/specs/2026-09-22-window-hijack-probe-results.md` (today's measurements, M1–M5) and GitHub issue [#34](https://github.com/Radiergummi/rfc-reader/issues/34) (what was tried before, and why each attempt failed). Read both before Task 1.

## Global Constraints

- **Branch off `reader-panel-overlay`**, which is the working overlay implementation and the fallback. It must stay green; never commit to it directly.
- **macOS only.** Every change is behind `#if os(macOS)`. iOS keeps `WindowGroup`, `NavigationSplitView` and `.inspector` exactly as they are; `ContentView` becomes an iOS-only view, and its body is not to be touched.
- **Never replace a `WindowGroup` window's `contentViewController`.** Measured: SwiftUI treats the scene as closed and opens a replacement window, which is then replaced in turn — 24 windows in 0.9 s. See M6.
- **The reader must not move.** Opening the panel must not change the window's size, the reader's width, the text's wrapping, or the scroll position. Verified by measurement, not by eye: window size identical before and after, and `magick compare -metric AE` over the reader region in the low single digits. Today's overlay scores **8 differing pixels in 1,280,000**; anything in the thousands means the text moved.
- **RFCKit knows nothing about SwiftUI; the app knows nothing about XML.** Unchanged by this work.
- **The App target has no test bundle.** Anything that is a pure function of its inputs belongs in `RFCReaderKit`. This plan is object-graph wiring — representables, controllers, view installation — which `CLAUDE.md` says belongs in the App target and can only be verified by running it. Every task therefore ends in a measurement, not a unit test. Do not invent a testable abstraction to have something to assert on.
- **Never assign `NSTextContentStorage.attributedString`**; write through `storage.textStorage?.setAttributedString(_:)`.
- **Ask for a decoration's extent with `longestEffectiveRange`, never `effectiveRange`.**
- **Anchors are stable strings**, never indices.
- The gate before every commit: `make check` (lint, build, test) and, for the app, `make build-app`. `swiftlint --strict` must stay clean; long lines cap at 200 characters. `make test-app` must pass at the end.
- `RFCReader.xcodeproj` is generated. New files land under `App/RFCReader/` and are picked up by `make xcodeproj`; never edit the project file.

## Measurement harness

Every task's verification uses these. Write them once, in the scratchpad, before Task 1.

`measure.sh` — launch the built app directly so stderr is ours (`open` detaches), with saved state cleared so restored tabs cannot stack windows and make diffs meaningless:

```bash
#!/bin/bash
# usage: measure.sh <label>
set -euo pipefail
APP="$(ls -d ~/Library/Developer/Xcode/DerivedData/RFCReader-*/Build/Products/Debug/RFCReader.app | head -1)"
rm -rf ~/Library/"Saved Application State"/*RFCReader* 2>/dev/null || true
pkill -f RFCReader.app || true
sleep 1
"$APP/Contents/MacOS/RFCReader" > "/tmp/rfcreader-$1.log" 2>&1 &
sleep 4
open "rfc://9110"        # a document without UI automation
sleep 6
osascript -e 'tell application "System Events" to tell process "RFCReader" to count of windows'
```

`window-id.sh` — the window to capture, so a screenshot is never of somebody else's window (this cost the previous session real time):

```bash
#!/bin/bash
osascript -e 'tell application "System Events" to tell process "RFCReader" to get value of attribute "AXIdentifier" of window 1' 2>/dev/null || true
# Preferred: the app logs its own window number; see ReaderWindowLayer.logWindowNumber().
grep -o 'RFCWINDOW number=[0-9]*' /tmp/rfcreader-*.log | tail -1 | grep -o '[0-9]*'
```

**Rules that come from the last session's wasted time:**
- Never pin the window with `osascript` while the bug under test *is* the window resizing.
- Always check the tab bar with **two** tabs, never one.
- Confirm `count of windows` is 1 before capturing anything.

---

### Task 1: Own the window

On macOS the app stops using `WindowGroup`. An app delegate creates every window; the scene is `Settings` alone, which still gives us the menu bar and `.commands` (M7). No toolbar work and no panel behaviour yet — this task is "the app still works, and AppKit owns the window".

**Files:**
- Create: `App/RFCReader/Window/ReaderWindowController.swift`
- Create: `App/RFCReader/Window/AppDelegate.swift`
- Create: `App/RFCReader/Model/AppData.swift`
- Modify: `App/RFCReader/RFCReaderApp.swift` (macOS: `Settings` + delegate adaptor + New Window/New Tab commands)
- Modify: `App/RFCReader/Views/ContentView.swift` (becomes iOS-only; `EmptyDetailView` and `GoToDocumentSheet` stay shared)

**Interfaces:**
- Consumes: `LibraryModel.shared`, `NavigationModel()`, `SidebarView`, `RFCListView`, `DocumentView`, `EmptyDetailView`, `GoToDocumentSheet`.
- Produces:
  - `AppData.container: ModelContainer` — the one SwiftData container, shared by every hosted root.
  - `final class ReaderWindowController: NSWindowController` with `let navigation: NavigationModel`, `let splitController: NSSplitViewController`, `private(set) var panelItem: NSSplitViewItem`, `@objc func newWindowForTab(_:)`, `static func controller(for: NSWindow) -> ReaderWindowController?`.
  - `final class AppDelegate: NSObject, NSApplicationDelegate` with `@discardableResult func openWindow(tabbedWith:) -> ReaderWindowController`.

- [ ] **Step 1: Write the measurement harness**

Save `measure.sh`, `capture.sh` and `winid.sh` into the scratchpad and `chmod +x` them. Run `measure.sh baseline` against a build of `reader-panel-overlay`, capture the window before and after ⌘⇧T, and record the reader-region `AE`. **Measured on this machine: window identical at 2800 × 2000 px, reader region `AE = 6` over `800x1200+1300+400`.** That is the number every later task is held to. Note the crop: `+300+200` lands in the list column, not the reader.

- [ ] **Step 2: Create the shared SwiftData container**

`App/RFCReader/Model/AppData.swift` — as written in the repo. `.modelContainer(for:)` was a scene modifier; there is no scene to hang it on any more, and each hosted root needs the *same* container or a bookmark written in one column will not appear in the next.

- [ ] **Step 3: Write the window controller**

`App/RFCReader/Window/ReaderWindowController.swift`. One per window, which is one per tab. It owns the `NavigationModel` that `ContentView` used to hold as `@State` — that ownership is what makes a tab a tab — and hands it, `LibraryModel` and the container to every hosted root explicitly, because an `NSHostingController` is outside any environment chain.

Key settings, each measured or required:
- `window.tabbingMode = .preferred` and a shared `tabbingIdentifier`, so new windows join as tabs.
- The four split items exactly as in M2/M3: sidebar (`sidebarWithViewController:`), list (`contentListWithViewController:`), reader (plain, `automaticallyAdjustsSafeAreaInsets = true`, `minimumThickness = ReaderLayout.minimumPaneWidth`), panel (`inspectorWithViewController:`, `allowsFullHeightLayout = true`, 320 pt, `isCollapsed = true`).
- `automaticallyAdjustsSafeAreaInsets` on the **content** item only. On the panel it does nothing useful; on the content item it is what lets the reader span the panel.
- `NSLog("RFCWINDOW number=\(window.windowNumber)")` — the harness reads it, and it is also how a churn like M6 would be caught immediately.

- [ ] **Step 4: Write the app delegate**

`App/RFCReader/Window/AppDelegate.swift`: opens the first window at launch, keeps the controllers alive (an `NSWindowController` with no owner is deallocated), opens a window again when the dock icon is clicked with none open, and takes `rfc://` links through `application(_:open:)` — which is where they have to be handled now that there is no scene to carry `onOpenURL`.

- [ ] **Step 5: Turn the scene into `Settings` and add the missing commands**

In `RFCReaderApp.swift`, on macOS: `@NSApplicationDelegateAdaptor(AppDelegate.self)`, a body of `Settings { SettingsView() }` carrying the existing `.commands`, and — because `WindowGroup` was what used to contribute them — a `CommandGroup(replacing: .newItem)` with **New Window** (⌘N) and **New Tab** (⌘T), both routed to the delegate. iOS keeps its `WindowGroup` unchanged.

- [ ] **Step 6: Build and run it**

Run: `make build-app` — expected: clean.
Run: `./measure.sh task1` — expected: **exactly one** `RFCWINDOW` line (more than one means the M6 churn is back), `windows: 1`, sidebar/list/reader showing real content, and `rfc://9110` opening the document.

- [ ] **Step 7: Commit**

```bash
git add App/RFCReader docs/superpowers
git commit -m "Let the app own its windows on macOS"
```

---

### Task 2: The toolbar, split at the panel's divider

**Files:**
- Create: `App/RFCReader/Window/ReaderToolbar.swift`
- Modify: `App/RFCReader/Window/ReaderWindowLayer.swift` (install the toolbar)
- Modify: `App/RFCReader/Views/DocumentView.swift:~250-300` (drop the macOS `.toolbar` content and the reserved-width spacer)
- Modify: `App/RFCReader/Views/ContentView.swift` (the `.navigation` Back/Forward item is now a toolbar item)

**Interfaces:**
- Consumes: `ReaderWindowLayer.splitController`, `.navigation`, `.panelItem`.
- Produces: `final class ReaderToolbar: NSObject, NSToolbarDelegate` with `init(layer: ReaderWindowLayer)` and `func makeToolbar() -> NSToolbar`; item identifiers `.rfcNavigation`, `.rfcDocumentActions`, `.rfcPanelSeparator`, `.rfcPanelToggle`.

- [ ] **Step 1: Write the toolbar delegate**

The separator's divider index is **2**: with four items the dividers are 0 (sidebar|list), 1 (list|reader), 2 (reader|panel). Measured in the spike at exactly this index.

```swift
#if os(macOS)
import AppKit
import SwiftUI

extension NSToolbarItem.Identifier {
    static let rfcNavigation = NSToolbarItem.Identifier("rfc.navigation")
    static let rfcDocumentActions = NSToolbarItem.Identifier("rfc.documentActions")
    static let rfcPanelSeparator = NSToolbarItem.Identifier("rfc.panelSeparator")
    static let rfcPanelToggle = NSToolbarItem.Identifier("rfc.panelToggle")
}

/// The window's toolbar.
///
/// `NSToolbar` only accepts items from its delegate, which is why the overlay
/// could never split it: SwiftUI owned the delegate. The item that does the
/// splitting is `NSTrackingSeparatorToolbarItem`, bound to the divider between
/// the reader and the panel — AppKit then lays the document's actions out in
/// what is left, and the panel's toggle sits out on the panel's own glass.
@MainActor
final class ReaderToolbar: NSObject, NSToolbarDelegate {
    private let layer: ReaderWindowLayer

    init(layer: ReaderWindowLayer) {
        self.layer = layer
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "rfc.reader")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .rfcNavigation, .flexibleSpace,
         .rfcDocumentActions, .rfcPanelSeparator, .rfcPanelToggle]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .rfcPanelSeparator:
            // Divider 2 of four items: reader | panel.
            return NSTrackingSeparatorToolbarItem(
                identifier: identifier,
                splitView: layer.splitController.splitView,
                dividerIndex: 2
            )
        case .rfcNavigation:
            return hosted(identifier, label: "Navigation", NavigationToolbarView())
        case .rfcDocumentActions:
            return hosted(identifier, label: "Document", DocumentActionsToolbarView())
        case .rfcPanelToggle:
            return hosted(identifier, label: "Contents", PanelToggleToolbarView())
        default:
            return nil
        }
    }

    /// SwiftUI inside a toolbar item, so the item's contents stay the declarative
    /// views they already were rather than being rewritten as AppKit controls.
    private func hosted(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        _ view: some View
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        let hosting = NSHostingView(
            rootView: view
                .environment(LibraryModel.shared)
                .environment(layer.navigation)
                .environment(\.readerWindowLayer, layer)
                .modelContainer(AppData.container)
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        return item
    }
}
#endif
```

- [ ] **Step 2: Move the toolbar's views out of `DocumentView`**

Create the three views in the same file. `NavigationToolbarView` is `ContentView`'s current `.navigation` item verbatim. `DocumentActionsToolbarView` is `DocumentView.toolbar`'s first `ToolbarItemGroup` — bookmark, cite, share, more — with one change: those actions need the current document, which the toolbar is not inside any more, so they read `navigation.selection` and `library.metadata(_:)` rather than `DocumentView`'s `@State`. Anything that genuinely needs the built document (copy link to current section, which needs `visibleAnchor`) reads it from `DocumentOutline` in Task 3; until then, omit that one menu entry and add it back in Task 3 rather than leaving a stub.

`PanelToggleToolbarView`:

```swift
private struct PanelToggleToolbarView: View {
    @Environment(\.readerWindowLayer) private var layer

    var body: some View {
        Button {
            layer?.togglePanel()
        } label: {
            Label("Contents", systemImage: "list.bullet.indent")
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
```

Delete from `DocumentView.swift`, inside `#if os(macOS)` only: the `ToolbarSpacer`, the reserved-width `ToolbarItem` (`Self.panelWidth - Self.toggleGroupWidth`) with its comment, the contents-toggle `ToolbarItem`, and `toggleGroupWidth`. The reserved width existed to do by hand what the tracking separator now does; leaving it in would reserve the panel's width twice.

- [ ] **Step 3: Add the environment key and the toggle**

In `ReaderWindowLayer.swift`:

```swift
extension EnvironmentValues {
    @Entry var readerWindowLayer: ReaderWindowLayer?
}
```

and on the layer:

```swift
/// Animated, so the panel slides rather than appearing between frames.
func togglePanel() {
    NSAnimationContext.runAnimationGroup { context in
        context.allowsImplicitAnimation = true
        panelItem.isCollapsed.toggle()
    }
}
```

In `install()`, after setting `contentViewController`:

```swift
toolbar = ReaderToolbar(layer: self)
window.toolbar = toolbar.makeToolbar()
window.toolbarStyle = .unified
```

(hold `ReaderToolbar` in a `private var toolbar: ReaderToolbar?` — `NSToolbar.delegate` is weak, and an unheld delegate gives an empty toolbar.)

- [ ] **Step 4: Build and measure the split**

Run: `make build-app && ./measure.sh task2` — expected: 1 window, toolbar shows sidebar toggle, back/forward, document actions, then the toggle.
Capture the titlebar: `screencapture -x -o -l "$(./window-id.sh)" task2.png && magick task2.png -crop x180+0+0 +repage task2-top.png`.
Expected, with the panel open: the toolbar's trailing group is the toggle alone, and the separator sits at `windowWidth - 320` pt (× 2 in pixels). With the panel collapsed the separator is at the window's trailing edge and the document's actions run out to it.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader/Window App/RFCReader/Views
git commit -m "Split the toolbar at the panel's divider"
```

---

### Task 3: The panel as a real split item

**Files:**
- Create: `App/RFCReader/Model/DocumentOutline.swift`
- Modify: `App/RFCReader/Window/ReaderWindowLayer.swift` (`PanelHost` becomes real; layer owns the outline)
- Modify: `App/RFCReader/Views/DocumentView.swift` (macOS: drop the overlay, write the outline)

**Interfaces:**
- Consumes: `DocumentInspector(sections:groups:tab:current:selectSection:openDocument:)`, `ReferenceGroup.groups(in:)`.
- Produces: `@Observable @MainActor final class DocumentOutline` with `var sections: [RFCKit.Section]`, `var groups: [ReferenceGroup]`, `var tab: InspectorTab`, `var current: String?`, `var hasDocument: Bool`.

- [ ] **Step 1: Write the shared outline**

The reader and the panel are two hosted controllers now, so what `DocumentView` used to hold as `@State` and read in its own `overlay` has to be somewhere both can see:

```swift
import Observation
import RFCKit

/// What the contents panel shows, shared between the reader and the panel.
///
/// These were `@State` on `DocumentView` while the panel was an overlay inside
/// it. The panel is its own split item now — its own hosting controller, its own
/// view tree — so the two sides meet here instead. One per window, like
/// `NavigationModel`: two tabs show two documents.
@Observable
@MainActor
final class DocumentOutline {
    var sections: [RFCKit.Section] = []
    var groups: [ReferenceGroup] = []
    var tab: InspectorTab = .contents
    /// The anchor the reader is looking at, for the contents' highlight and for
    /// "copy link to this section" in the toolbar.
    var current: String?
    var hasDocument = false

    func clear() {
        sections = []
        groups = []
        current = nil
        hasDocument = false
    }
}
```

Hold one on `ReaderWindowLayer` (`let outline = DocumentOutline()`), inject it into every hosted root beside the other two models, and add `@Environment(DocumentOutline.self)` where it is read.

- [ ] **Step 2: Make the panel host real**

```swift
private struct PanelHost: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(DocumentOutline.self) private var outline

    var body: some View {
        @Bindable var outline = outline
        if outline.hasDocument {
            DocumentInspector(
                sections: outline.sections,
                groups: outline.groups,
                tab: $outline.tab,
                current: outline.current,
                selectSection: { navigation.jump(toSection: $0) },
                openDocument: { library.open($0, activation: .current, in: navigation) }
            )
            // Without this the list draws its own opaque sidebar background over
            // the inspector's glass, and the panel stops being translucent.
            .scrollContentBackground(.hidden)
        } else {
            Color.clear
        }
    }
}
```

- [ ] **Step 3: Have `DocumentView` write the outline instead of drawing an overlay**

In `DocumentView.swift`, inside `#if os(macOS)`: delete the whole `.overlay(alignment: .trailing) { … }` block, `showTableOfContents`, `panelWidth`, and the `inspector` property's macOS use (iOS still uses it for `.inspector`). Keep `bodySections`/`referenceGroups` as the local derivation they already are, and mirror them:

```swift
#if os(macOS)
.onChange(of: bodySections, initial: true) { outline.sections = bodySections }
.onChange(of: referenceGroups, initial: true) { outline.groups = referenceGroups }
.onChange(of: visibleAnchor) { outline.current = visibleAnchor }
.onChange(of: document == nil, initial: true) { outline.hasDocument = document != nil }
.onDisappear { outline.clear() }
#endif
```

Add back the toolbar's "Copy Link to Current Section" entry from Task 2, reading `outline.current`.

- [ ] **Step 4: Measure that the reader did not move**

This is the constraint three earlier attempts died on.

```bash
make build-app && ./measure.sh task3
WIN=$(./window-id.sh)
screencapture -x -o -l "$WIN" closed.png
osascript -e 'tell application "System Events" to tell process "RFCReader" to keystroke "t" using {command down, shift down}'
sleep 2
screencapture -x -o -l "$WIN" open.png
sips -g pixelWidth -g pixelHeight closed.png open.png     # must be identical
magick compare -metric AE \
  \( closed.png -crop 800x1200+300+200 +repage \) \
  \( open.png   -crop 800x1200+300+200 +repage \) null: 2>&1
```

Expected: identical window dimensions, and an `AE` count in the single digits over the reader region (today's overlay: 8 of 1,280,000). Thousands means the text moved — stop and fix before going on; do not carry this into Task 4.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader
git commit -m "Make the contents panel a real split view item"
```

---

### Task 4: The reader ignores the panel's safe-area inset

The content item hands the panel's width back as a right safe-area inset (spec M3: `safeR=320`). #34 measured that `ignoresSafeArea` does **not** undo an AppKit-level inset, so this is fixed in the representable.

**Files:**
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift` (the `#else` / AppKit `Representable`)

**Interfaces:**
- Consumes: the `NSScrollView` built in `makeNSView`.
- Produces: no new API.

- [ ] **Step 1: Confirm the symptom before fixing it**

With the panel open, log the reader's geometry once from `updateNSView`:

```swift
NSLog("RFCREADER scroll=\(scroll.frame.width) safeR=\(scroll.safeAreaInsets.right) width=\(width)")
```

Expected before the fix: `safeR=320` and `width` short by 320 — the reader re-wrapped, which is the bug.

- [ ] **Step 2: Make the scroll view ignore it**

In `makeNSView`, after the scroll view is built:

```swift
// The panel is a split item, so the reader's frame spans it and AppKit hands
// the panel's width back as a right safe-area inset. Honouring it would take
// 320 pt off the column the moment the panel opened — which re-wraps the text,
// rebuilds the document and loses the reader's place, the exact thing the
// overlay existed to avoid. What the panel overlaps, it covers.
scroll.automaticallyAdjustsContentInsets = false
scroll.contentInsets = NSEdgeInsetsZero
scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
```

If the hosted SwiftUI root still reports the inset to `GeometryReader` — check the logged `width` — take the width from the scroll view's own frame rather than from `geometry.size.width` on macOS, since the representable is the side of the line where this arithmetic belongs.

- [ ] **Step 3: Measure**

Run the Task 3 Step 4 measurement again, and additionally confirm from the log that `width` with the panel open equals `width` with it closed. Expected: equal, and the `AE` count unchanged from Task 3.

Also confirm the scroller does not end up under the glass: with the panel open, the vertical scroller should sit at the reader's own trailing edge, under the panel — that is what "covered" means — and reappear when the panel closes.

- [ ] **Step 4: Commit**

```bash
git add App/RFCReader/Views/Rendering/RFCTextView.swift
git commit -m "Keep the reader's full width under the contents panel"
```

---

### Task 5: Tabs

Much of this is already standing after Task 1 — the windows are ours, so tabs are `addTabbedWindow`. What is left is routing the app's own "open in a new tab" through it, and the window title.

**Files:**
- Modify: `App/RFCReader/Window/ReaderWindowController.swift` (title observation)
- Modify: `App/RFCReader/Window/AppDelegate.swift` (`openWindow(tabbedWith:)`)
- Modify: `App/RFCReader/Model/LibraryModel.swift` (`openInNewScene`)

**Interfaces:**
- Produces: `AppDelegate.openWindow(tabbedWith: ReaderWindowController?, inBackground: Bool) -> ReaderWindowController`.

- [ ] **Step 1: Open a tab from the app**

A new `ReaderWindowController`, joined to the current one with `addTabbedWindow(_:ordered: .above)`. Measured working, no churn: `SPIKE2 windows=2 tabs=2` (M8). `newWindowForTab(_:)` on the window controller answers the tab bar's `+` and ⌘T, because with no `WindowGroup` nothing else does.

- [ ] **Step 2: Route `LibraryModel.openInNewScene` through it**

```swift
private func openInNewScene(_ link: RFCLink, inBackground: Bool) {
    #if os(macOS)
    pendingSceneLink = link
    let current = NSApp.keyWindow.flatMap(ReaderWindowController.controller(for:))
    AppDelegate.shared?.openWindow(tabbedWith: current, inBackground: inBackground)
    #endif
}
```

`pendingSceneLink` still works unchanged: the new controller calls `library.register(navigation)` as it is built, which is where the pending link is taken.

- [ ] **Step 3: Give the window its title**

`navigationTitle`/`navigationSubtitle` came from `ContentView`, which macOS no longer instantiates. The controller sets them directly, tracking the navigation with `withObservationTracking` and re-arming on each change. Keep the 64-character subtitle limit and its reasoning: a tab is far narrower than the window and clips rather than eliding.

- [ ] **Step 4: Measure with two tabs**

```bash
make build-app && ./measure.sh task5
osascript -e 'tell application "System Events" to tell process "RFCReader" to keystroke "t" using {command down}'
sleep 3
osascript -e 'tell application "System Events" to tell process "RFCReader" to count of windows'   # 2
./capture.sh tabs.png "$(./winid.sh task5)"
magick tabs.png -crop x200+0+0 +repage tabs-top.png
```

Expected: two tabs, each titled for its own document; with the panel open the tab bar **ends at the panel's leading edge** — `(windowWidth - 320)` pt — instead of running under it. That is the issue. Also check ⌘-clicking a cross reference opens a background tab, and that the tab bar's `+` works.

The app also logs the geometry, which is the evidence that does not need a screenshot:

```swift
NSLog("RFCGEOM window=\(window.frame.width) reader=\(readerItem.viewController.view.frame.width) safeR=\(readerItem.viewController.view.safeAreaInsets.right) panelCollapsed=\(panelItem.isCollapsed)")
```

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader
git commit -m "Open tabs from the window controller"
```

---

### Task 6: Menu commands, deep links and search

The three things the scene used to do for views that are no longer in it.

**Files:**
- Modify: `App/RFCReader/RFCReaderApp.swift` (`DocumentCommands`, an app delegate for URLs)
- Modify: `App/RFCReader/Window/ReaderWindowLayer.swift` (key-window tracking)
- Modify: `App/RFCReader/Views/SidebarView.swift` (search placement, if needed)

**Interfaces:**
- Produces: `@Observable @MainActor final class ActiveReaderWindow` with `static let shared` and `private(set) var layer: ReaderWindowLayer?`.

- [ ] **Step 1: Find out whether focused values still resolve**

Unmeasured (spec M5), and it decides the rest of this task. With Task 5 built, check the menu: does ⌘L open the Go to RFC sheet, and do Back/Forward enable and disable with the history?

If they work, skip Steps 2–3 and say so in the commit message. If they do not — the likely case, since `focusedSceneValue` is published from views inside an `NSHostingController` outside the scene — continue.

- [ ] **Step 2: Track the key window**

```swift
/// Which window the menu acts on.
///
/// `@FocusedValue` published from a hosted root does not reach the scene's
/// commands, so the menu asks the key window instead. This is closer to what
/// the menu means anyway: Back acts on the tab you are looking at.
@Observable
@MainActor
final class ActiveReaderWindow {
    static let shared = ActiveReaderWindow()
    private(set) var layer: ReaderWindowLayer?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self.layer = ReaderWindowLayer.layer(for: window) ?? self.layer
            }
        }
    }
}
```

- [ ] **Step 3: Rewire the commands**

In `DocumentCommands`, replace the two `@FocusedValue` lookups with reads of `ActiveReaderWindow.shared.layer?.navigation`, keeping the shortcuts and the always-present-but-dimmed behaviour:

```swift
#if os(macOS)
@State private var active = ActiveReaderWindow.shared
private var navigation: NavigationModel? { active.layer?.navigation }
#else
@FocusedValue(\.navigationModel) private var navigation
#endif
```

⌘L becomes `active.layer?.navigation.isShowingGoToSheet = true`; the sheet is presented by `ReaderHost`, which is in the window.

- [ ] **Step 4: Take deep links through the app delegate**

`onOpenURL` is declared on the scene's detached view tree. Rather than depend on whether it still fires, handle it where it cannot be detached:

```swift
#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                if let link = RFCLink(url: url) { LibraryModel.shared.route(link) }
            }
        }
    }
}
#endif
```

Adopt it with `@NSApplicationDelegateAdaptor(AppDelegate.self)` on `RFCReaderApp`, and delete the macOS `onOpenURL` (keep it for iOS). Move `library.bootstrap()` out of the scene's `.task` and into `ReaderWindowLayer.install()` (guarded — `bootstrap()` already no-ops when not `.idle`), because a detached view tree's `.task` may never run.

- [ ] **Step 5: Decide search**

`.searchable(text:placement:.sidebar)` is declared on `SidebarView`, which no longer sits in a `NavigationSplitView`. If Task 1 Step 6 found the field missing, put it in the sidebar's own content rather than in the toolbar:

```swift
.safeAreaInset(edge: .top) {
    TextField("Search", text: $navigation.searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
}
```

**Not** an `NSSearchToolbarItem`: the toolbar's trailing end belongs to the panel's toggle, and the document section is the wrong place for a filter that acts on the library. Record which of the two shipped in the commit message and in `ARCHITECTURE.md`.

- [ ] **Step 6: Verify the whole surface**

Run through, with two tabs open:
- ⌘L opens the sheet, types `9110`, opens it.
- ⌘← / ⌘→ move through history and dim at the ends.
- `open "rfc://9110"` lands in one tab only, the one already showing it if there is one.
- ⌘F opens the find bar in the reader; ⌘G steps matches.
- ⌘D bookmarks; the sidebar's Bookmarks filter shows it (proves one SwiftData container, not two).
- Search filters the list.
- Quit and relaunch: the reading position is restored.

- [ ] **Step 7: Commit**

```bash
git add App/RFCReader
git commit -m "Reach the reader's commands from the key window"
```

---

### Task 7: Green the gate and record the decision

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `CLAUDE.md` (the standing-constraints list)

- [ ] **Step 1: Run the gate**

```bash
make check && make test-app && swiftlint lint --strict
```

Expected: all pass, no warnings. Fix anything this work introduced; do not fix pre-existing dead code.

- [ ] **Step 2: Record the decision**

Add a dated entry to `docs/ARCHITECTURE.md` covering: that `WindowGroup` still owns the scene while AppKit owns the window's content on macOS; that the panel is an `NSSplitViewItem`, which is what confines the tab bar and splits the toolbar; that the reader ignores the resulting safe-area inset in the representable and why a SwiftUI modifier cannot; and that a tab is made by invoking SwiftUI's New Window and joining it with `addTabbedWindow`. Link the probe spec.

Add to `CLAUDE.md`'s standing constraints, in the same voice as the others:

> **A hosted root is outside the environment chain.** Every `NSHostingController` the window layer creates is handed `LibraryModel`, `NavigationModel`, `DocumentOutline` and the SwiftData container explicitly. An `@Environment` lookup inside one is a runtime trap with no compile-time warning.

- [ ] **Step 3: Final measurement, recorded**

Re-run the Task 3 Step 4 diff and the Task 5 tab-bar capture on the final build, and post both to issue #34 with the numbers. Close it if the tab bar is confined.

- [ ] **Step 4: Commit**

```bash
git add docs CLAUDE.md
git commit -m "Record the window layer's decisions"
```

---

## Self-review

**Spec coverage.** M1 (the hijack holds) → Task 1. M2 (chrome engages) → Tasks 2 and 5, verified by capture. M3 (safe-area inset) → Task 4, and the `automaticallyAdjustsSafeAreaInsets` placement in Task 1 Step 3. M4 (tab creation) → Task 5. M5 (focused values unknown) → Task 6 Step 1, which branches on the answer rather than assuming it. The handoff's "reader keeps its full width underneath" → Task 3 Step 4 and Task 4 Step 3, both by measurement. The handoff's "say what you chose about search" → Task 6 Step 5.

**Placeholders.** The one deliberate stub is `PanelHost` in Task 1, which Task 3 Step 2 replaces in full; Task 1 Step 3 says so at the stub. Task 2 Step 2 defers exactly one menu entry to Task 3 Step 3 rather than leaving a stub behind.

**Type consistency.** `ReaderWindowLayer.layer(for:)`, `.navigation`, `.splitController`, `.panelItem`, `.togglePanel()`, `.openTab(inBackground:)` are named the same in Tasks 1, 2, 3, 5 and 6. `DocumentOutline`'s five properties are written in Task 3 Step 1 and read in Step 2 and Step 3 under those names. `panelWidth` is `ReaderWindowLayer.panelWidth` after Task 2 removes `DocumentView`'s copy.

**Known risk, not designed around.** If Task 1 Step 6 shows SwiftUI tearing the scene down when its view tree is detached — nothing in the 28-second probe suggested it, but the probe was not a full app — the fallback is the full AppDelegate rewrite in issue #34, and `reader-panel-overlay` is still the shipping branch. Say so early with the measurement rather than half-landing this.
