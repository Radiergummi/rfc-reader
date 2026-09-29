import Foundation
import RFCKit

/// What a request for a new window on iPad carries (#158): the link to open, in an
/// `NSUserActivity`'s user info.
///
/// An activity per request, rather than one pending link the next scene takes, so
/// two windows asked for in quick succession cannot swap their documents. The
/// activity arrives only as the scene is made: a window iPadOS restores after a
/// relaunch comes back on the library, which is #155's to change. The link travels
/// as its `rfc://` URL, the form a deep link already arrives in.
public enum SceneRequest {
  public static let activityType = "me.mazetti.rfc-reader.open"
  static let linkKey = "link"

  public static func userInfo(for link: RFCLink) -> [String: String] {
    [linkKey: link.appURL.absoluteString]
  }

  /// The link an activity carries, or nil when it carries none this app reads.
  public static func link(from userInfo: [AnyHashable: Any]?) -> RFCLink? {
    guard let string = userInfo?[linkKey] as? String, let url = URL(string: string) else {
      return nil
    }
    return RFCLink(url: url)
  }
}
