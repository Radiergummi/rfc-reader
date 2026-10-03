import SwiftUI

/// What a scene's size classes say about its chrome, worked out once by the scene
/// and read by every view that lays itself out by it (#257). Each view used to read
/// a size class of its own and spell the question itself.
public struct SceneChrome: Sendable, Equatable {
  /// The split view is one stack, as on an iPhone: the panel is a sheet over the
  /// reader, and the system's back button is the way out of a document.
  public var isCollapsed: Bool
  /// The bars are short, as on a phone held sideways, and the title in the bar is
  /// set on one line.
  public var hasShortBars: Bool

  /// No size class, as SwiftUI passes before a scene has traits, reads as side by
  /// side with tall bars.
  public init(horizontal: UserInterfaceSizeClass? = nil, vertical: UserInterfaceSizeClass? = nil) {
    isCollapsed = horizontal == .compact
    hasShortBars = vertical == .compact
  }
}

extension EnvironmentValues {
  /// The scene's chrome, set by the scene's root from its size classes.
  @Entry public var sceneChrome = SceneChrome()
}
