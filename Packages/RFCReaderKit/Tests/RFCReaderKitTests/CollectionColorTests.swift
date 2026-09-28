import Foundation
import Testing

@testable import RFCReaderKit

/// A collection's colour, stored by name so it syncs as a word (#349).
@Suite("Collection colour")
struct CollectionColorTests {
  @Test func `every colour round-trips through its name`() {
    for color in CollectionColor.allCases {
      #expect(CollectionColor(name: color.rawValue) == color)
    }
  }

  /// What a newer device may sync to an older one.
  @Test func `an unknown name reads as the default`() {
    #expect(CollectionColor(name: "chartreuse") == .default)
    #expect(CollectionColor.default == .blue)
  }

  @Test func `the palette is in the order the swatches show it`() {
    #expect(
      CollectionColor.allCases.map(\.rawValue) == [
        "blue", "green", "orange", "red", "purple", "pink", "teal", "yellow", "gray",
      ])
  }
}
