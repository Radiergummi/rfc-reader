import Foundation
import SwiftData

/// User data lives in SwiftData so iCloud sync is a one-line change later.

@Model
final class Bookmark {
  @Attribute(.unique) var number: Int
  var title: String
  var createdAt: Date

  init(number: Int, title: String) {
    self.number = number
    self.title = title
    self.createdAt = .now
  }
}

@Model
final class ReadingPosition {
  @Attribute(.unique) var number: Int
  /// Anchor of the section that was on screen when the reader left.
  var sectionAnchor: String?
  var updatedAt: Date

  init(number: Int, sectionAnchor: String?) {
    self.number = number
    self.sectionAnchor = sectionAnchor
    self.updatedAt = .now
  }
}
