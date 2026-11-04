import Foundation
import os

/// The kit's intervals, in the app's Points of Interest lane: the same subsystem and
/// category as the app's `signposter`, so `make trace` reads them as the app's.
let signposter = OSSignposter(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader",
  category: .pointsOfInterest
)
