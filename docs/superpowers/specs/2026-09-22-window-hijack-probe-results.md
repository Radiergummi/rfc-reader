# Window hijack: probe results

**Date:** 2026-09-22
**Context:** [#34](https://github.com/Radiergummi/rfc-reader/issues/34) — the contents panel confines neither the window tab bar nor the toolbar.
**Outcome:** #34's conclusion stands — the window must be ours from birth — but
for a reason it never named, and at a lower cost than it assumed. Round one below
tested hijacking a `WindowGroup` window and looked like it worked; round two
measured it in the real app and it does not. Read both before proposing a fifth
approach.

Issue #34 measured four approaches and concluded that AppKit window chrome
engages only for a split view controller that *is* the window's root, and that
getting one there means the app must create its own windows — giving up SwiftUI
scene management, `.commands`, the menu bar, `onOpenURL` and window tabs.

The step between those two statements was never measured: a window created by
`WindowGroup` can have its `contentViewController` **replaced** after the fact.
The scene keeps existing; only its view tree is detached. This spec records what
that does, measured on a standalone spike (`spike.swift`, macOS 26, arm64).

## The spike

A SwiftUI `WindowGroup` containing a `NavigationSplitView` and a `.toolbar`.
Once the window exists, a `NSViewRepresentable` in its `.background` replaces
`window.contentViewController` with an `NSSplitViewController` holding four
items, and `window.toolbar` with an `NSToolbar` owned by our own delegate:

| Item | Constructed with | Notes |
|---|---|---|
| 0 sidebar | `NSSplitViewItem(sidebarWithViewController:)` | `minimumThickness = 180` |
| 1 list | `NSSplitViewItem(contentListWithViewController:)` | `minimumThickness = 240` |
| 2 reader | `NSSplitViewItem(viewController:)` | `automaticallyAdjustsSafeAreaInsets = true` |
| 3 panel | `NSSplitViewItem(inspectorWithViewController:)` | `allowsFullHeightLayout = true`, 320 pt |

Toolbar items: `.toggleSidebar`, `.flexibleSpace`, an action item,
`NSTrackingSeparatorToolbarItem(identifier:splitView:dividerIndex: 2)`, a toggle.

## M1 — The hijack holds

`contentViewController` stays ours. The scene root drives a 0.3 s timer that
mutates `@State`, so SwiftUI reconciled the (detached) scene roughly 90 times
over the run. Probed at t=10 s, 20 s and 28 s, across three windows:

```
SPIKE durability t=10.0 window[0] ours=true toolbarItems=5 tabs=3
SPIKE durability t=20.0 window[1] ours=true toolbarItems=5 tabs=3
SPIKE durability t=28.0 window[2] ours=true toolbarItems=5 tabs=3
```

SwiftUI never reinstalls its own `contentViewController` and never takes the
toolbar back. This is the measurement that separates the hijack from #34's
attempt 3, where SwiftUI *did* reconcile away an added `splitViewItem`: there we
mutated SwiftUI's controller, here we replace it.

## M2 — Window chrome engages

Captured by window id (`screencapture -l`), window 741 × 500 pt, panel 320 pt,
so the panel's leading edge is at **421 pt**:

- The window tab bar — two tabs and the `+` — ends at **845 px of 1482 px**,
  i.e. **422 pt**. It stops at the panel's leading edge instead of running under
  it. This is the thing #34 could not get.
- The toolbar splits at the same divider. The contents toggle sits alone on the
  panel's side; the document's action is in the document's section.

## M3 — The reader extends underneath

```
SPIKE item[2] behavior=0 collapsed=false frame=320.0 safeR=320.0 autoSafe=true
SPIKE item[3] behavior=3 collapsed=false frame=320.0 safeR=0.0  autoSafe=false
```

The content item's frame spans the panel; the panel's width comes back as a
**right safe-area inset of 320**, exactly as #34 measured in a pure-AppKit
window. `automaticallyAdjustsSafeAreaInsets` belongs on the *content* item.

Consequence for the reader: the inset must be ignored inside the representable.
#34 already measured that `ignoresSafeArea` does not undo an AppKit-level inset.

## M4 — Tab creation breaks, and is re-implementable

`NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)`
— what `LibraryModel.openInNewScene` uses today — finds no handler once SwiftUI's
hosting controller is out of the responder chain:

```
SPIKE opening second tab
SPIKE probe[0] ... tabs=0
```

But SwiftUI's own File ▸ New Window menu item still creates a scene, that new
window gets hijacked by its own installer, and `addTabbedWindow(_:ordered:)`
joins it to the first:

```
SPIKE found menu item action=Optional(menuAction:) target=Optional(SwiftUI…MenuItemCallback)
SPIKE before hijack: contentVC=Optional<NSViewController>
SPIKE after hijack:  contentVC=Optional<NSViewController> items=4
SPIKE new windows=1
SPIKE tabbed; first.tabs=2
```

So a tab is: invoke SwiftUI's New Window, wait for the window, tab it in. The
window's own `+` button also needs `newWindowForTab(_:)` implemented somewhere in
our responder chain, because nothing answers it any more.

## M5 — Focused values: not measured

The probe drove a `@FocusedValue`-backed command by sending its menu item's
action programmatically, and got `nil` — **but so did the control run with the
hijack disabled**, so the probe measures the probe, not the hijack:

```
SPIKE control run: no hijack
SPIKE focusedValue=nil
```

Whether `@FocusedValue` / `focusedSceneValue` still resolve when the publishing
views live in an `NSHostingController` outside the scene's view tree is
**unknown**. It decides whether ⌘L and ⌘←/⌘→ keep working as written. Treat it
as "assume broken, verify in the real app": the fallback — menu commands reading
the key window's layer — is deterministic and not much larger.

## What round one concluded — and why it was wrong

Round one read as: the window layer can be AppKit-owned without giving up the
scene. Every measurement in it is real, and M2 and M3 still hold. What it missed
is that none of its runs counted windows over time, so the churn in M6 was
invisible. The lesson is narrower than "spikes lie": a spike that never clears
saved application state cannot tell a restored window from one the app just
made, and this one had an unexplained extra window in *every* run.

---

## Round two: the hybrid fails in the real app

Everything above was measured on the spike. Built into RFCReader, the hijack does
something the spike never revealed.

### M6 — SwiftUI replaces a window whose content it loses

`ReaderWindowLayer.install()` logs its window number. At launch:

```
RFCWINDOW number=39063
RFCWINDOW number=39064
…
RFCWINDOW number=39082      (24 windows in 0.9 s, ~38 ms apart)
```

Each number is a distinct `NSWindow`. Setting `window.contentViewController` to
our split controller makes `WindowGroup` treat the scene as closed and open a
replacement window, which the installer hijacks in turn. The churn is bounded
(it settles after ~25) but the app is left with zero or one window and a scene
in an unclear state. Three variants, all measured, all churn:

| Variant | Windows created |
|---|---|
| Drop SwiftUI's controller | 25+ |
| Park its view in ours, hidden | 25 |
| Park its view in ours, visible, zero-sized | 27 |
| Scene root shaped like the spike (`NavigationSplitView` + `.background`) | 26 |

The spike did not look like it churned because its runs never cleared saved
state and never counted windows over time — the "extra" windows in the spike's
run 2 and control run were this, misread as state restoration. The control run
having *more* extra windows than the hijacked run should have been the tell.

**Conclusion: a window created by `WindowGroup` cannot have its content view
controller replaced.** The window has to be ours from birth, which is what issue
#34 concluded for different reasons.

### M7 — The menu bar survives without `WindowGroup`

The rewrite's largest unknown was whether losing `WindowGroup` means rebuilding
the entire main menu in AppKit. It does not. A `Settings`-only scene with
`@NSApplicationDelegateAdaptor`, windows created by the delegate:

```
SPIKE2 menu: ["Spike2", "File", "Edit", "View", "Window", "Help"]
SPIKE2 File menu: ["Custom Command", "", "Close", "Close All"]
SPIKE2 Edit menu has 17 items: ["Undo", "Redo", "", "Cut", "Copy", "Paste", "Delete", "Select All"]
SPIKE2 Window menu: ["Minimize", "Zoom", "", "Bring All to Front", "", "Spike2"]
```

SwiftUI still builds the menu bar and still honours `.commands` — "Custom
Command" is the app's own, injected with `CommandGroup(after: .newItem)`. What
is missing is what `WindowGroup` used to contribute: **New Window**. That, and
New Tab, become our own command group.

### M8 — Our own windows tab

With windows created by an `NSWindowController` and joined with
`addTabbedWindow(_:ordered:)`:

```
SPIKE2 windows=2 tabs=2
SPIKE2 window number=39210 frame=(0.0, 200.0, 801.0, 500.0) vc=Optional<NSViewController>
SPIKE2 window number=39212 frame=(0.0, 200.0, 801.0, 500.0) vc=Optional<NSViewController>
```

No churn, `newWindowForTab(_:)` answered by the window controller, the four-item
split controller and the tracking separator installed as in M2.

### What survives from round one

M2 and M3 are properties of the split controller and are unaffected by who
creates the window: the tab bar stops at the panel's leading edge, the toolbar
splits at divider 2, and the content item reports `safeAreaInsets.right = 320`.
Those were measured in a window whose root was ours, which is what the app now
builds.
