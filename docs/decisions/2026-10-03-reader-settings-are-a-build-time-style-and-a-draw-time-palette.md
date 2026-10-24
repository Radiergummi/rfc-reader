# Reader settings are a build-time style and a draw-time palette

*Decided October 2026, as the first slice of the customization epic (#702, #703).*
Every reader setting is one of two kinds, and its type says which.
A **build-time** setting changes the attributed string, so it is part of `ReadingStyle`: the font size, the measure, underlined links, which captions and chips are emitted, and the syntax theme, whose colors the builder writes into a code block's runs.
A change costs a rebuild, which loses the reader's place until the anchor index puts it back, and `ReadingStyle` keys the preview cache (`BuildKey`), so a kept preview of the old style is not reused.
A **draw-time** setting is a color `RFCTextLayoutFragment` resolves as it draws, so it is part of `ReaderPalette`: the card and aside fills, the quote's rule, a decorated block's strokes, the chip tint, and the page background.
A change only redraws, and is not part of `BuildInputs`, so a theme switch never costs the reader's place.
A setting that could be either is draw-time: the palette is where page themes (#704) and the theme editor (#709) are cheap, and a setting moved to the style later costs only a rebuild.

`ReaderSettings` (RFCReaderKit) decodes every key of `ReaderPreferences` into one value, falling back to the default for anything absent, of the wrong type or unknown to this version, and clamping the size into its range; it writes back only what changed, so a setting nobody touched stays unstored and follows its default if that moves.
It makes the style for a column (`style(column:textSize:)`) and carries the palette.
A view reads it through `@ReaderSettingsValue`, a property wrapper whose storage is an `@AppStorage` per key.
A model handed down the environment was the alternative the issue proposed, and is not what was built: the window's hosted roots and the menu commands sit outside any SwiftUI environment chain, where an `@Environment` lookup traps at run time with no warning at compile time, and every new `NSHostingController` would have to remember to pass it.
User defaults reach every root without that.
The wrapper decodes through `ReaderSettings.init`, as `init(defaults:)` does for what reads outside a view, a print or an export, so the decoding exists once.
The menu commands' Bigger, Smaller and Actual Size, and the iPad's hidden ⌘=, still step the size through an `@AppStorage` of that one key: the key and its default are `ReaderPreferences`', and a custom property wrapper in a `Commands` struct was not worth the risk for one number.

Each layout manager of built text gives its fragments a `ReaderPaletteBox`, a palette behind a lock, read on whatever thread TextKit draws on.
A box rather than a value handed to each fragment: TextKit keeps the fragments it laid out, and a theme switch has to recolor them without laying them out again.
The reader's coordinator owns its box and replaces the palette on the main actor when the setting changes, then asks for a redraw; a print's fragments get `RFCTextLayoutFragment.paper`, the automatic palette, which its forced light appearance resolves to a white page's (2026-09-29), whatever the screen's theme.

`SyntaxTheme` and `ReaderPalette` are equal by identifier alone.
Both hold dynamic `PlatformColor`s, which compare by identity, and `ReadingStyle` has to be `Hashable` to key the cache.
An identifier is also what user defaults store, so a theme removed in a later version, or stored by a newer one, reads as the default (`named(_:)`).
A theme edited in place therefore needs a new identifier, as a reader's edited copy will get one (#709).

Settings on iOS are a screen of the app's own, `SettingsScreen`, from the reader's text size menu and the library's menu, built from the same sections as the Mac's tabs.
Not a settings bundle in the Settings app, which was weighed (#702): it can show no preview, no color picker and no list made at run time, such as a reader's own themes or the installed fonts, it validates nothing, and since iOS 18 it is a level deeper, under Apps.
Apple keeps it for settings changed rarely; the Settings app will hold the system-level kind, such as downloads and network use, when there is one.

## Amended: the text's colors (#704, October 2026)

Page themes (#704) make the text's own colors draw-time too: body text, secondary text, links, the page and the selection.
The plan was rendering attributes, set by an `NSTextLayoutManager` validator as each fragment is drawn, the path the card-link color takes.
A probe on #704's branch (2026-10-19, on #702) showed they do not survive the reader's redraw: the validator runs once per fragment, and after `invalidateRenderingAttributes` (`ReaderLayoutEngine.redraw`, #747) the text drew in the stored colors again, while re-applying them over every fragment after each redraw cost about 0.35 s over RFC 9110 in a debug build, against 1.31 s for a rebuild.

What was built instead, the maintainer's choice of 2026-10-19: the builder stores, in place of `RFCColors.label` and `.secondaryLabel`, `ReaderPalette.themedText` and `.themedSecondaryText`, dynamic colors whose provider returns the color of the theme chosen for the appearance they are resolved in.
The light and the dark theme chosen are process-wide, behind a lock (`ReaderPalette.choose(light:dark:)`), kept to user defaults as each change is written (`ReaderPalette.follow()`), so a theme switch costs what a switch to dark mode costs: a redraw, with no per-fragment work, and any later redraw keeps it.
Links keep the layout manager delegate's path (`LinkRendering`), which the same probe found holds at draw time; the page is the scroll view's background, and on macOS the selection is the text view's selected-text attributes.
A print and an exported PDF build with the system's label colors (`ReadingStyle.followsPageTheme` off), so paper keeps the paper palette whatever the screen's theme.
The syntax colors (#707) are to take the same path.
