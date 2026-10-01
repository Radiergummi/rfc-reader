import Foundation
import os

/// The app's signposts: the costs a person waits for, as intervals in Instruments'
/// Points of Interest lane, and what `make trace` reads back.
///
/// Points of Interest rather than a category of our own, because every Instruments
/// template records that lane, Time Profiler included, so a trace needs no custom
/// template to show them. A signposter costs next to nothing while nothing records,
/// so these stay in Release builds, which are the ones worth measuring.
///
/// Each interval carries the document it is about, as public metadata, so a trace
/// over several opens can tell them apart. "Lay out document" is the exception to
/// reading an interval as time the interface waited: it spans every slice of the
/// background completion, and the frames drawn between them, so it says when the
/// document was complete, not how long the main thread was held. "Settle" is what a
/// jump, an install or a change of column holds the main thread for, laying out
/// everything above the reader's line at once (`PinRecipe.settle`); next to nothing
/// once completion has passed the line. It falls inside "Lay out document", so the
/// two don't add up.
nonisolated let signposter = OSSignposter(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader",
  category: .pointsOfInterest
)
