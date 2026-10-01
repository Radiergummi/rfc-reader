import RFCKit

/// The open tabs a link is routed through, most recently used first, and the links
/// waiting for a tab (#137). Pure, over any kind of tab, so the routing is tested here
/// rather than in the App target, which carries out its decisions.
///
/// One place decides, because `onOpenURL` is delivered to every open scene: without
/// it, a deep link would open in all of them at once. Tabs are held weakly: a tab's
/// lifetime is its window's, and nothing here should keep a closed one alive.
///
/// A link waits until there is a tab to take it and the index has arrived or failed
/// to (#241). On a cold launch the first tab registers before the index is read, and
/// a BCP or STD link handed over then would select the series itself, because
/// resolving it to its first RFC needs the index. Every link waits, not only a
/// series': the wait is usually the time the index takes to read from the cache, and
/// one rule is easier to trust than two. On a first launch with no cached index and no
/// snapshot bundled with the app, it is the index's download.
///
/// Two kinds of link wait, apart, so that neither displaces the other:
/// - **For a new tab**, opened behind or in front from a tab already open: in order,
///   one per tab, each bound to the next tab to register. One whose tab closes before
///   it is delivered is dropped: the tab it was made for is gone, and the tab in use
///   did not ask for it.
/// - **Routed from outside**, before the index arrived or with no tab to take it. One
///   slot: of two, the later wins, being the more recent ask, and the first tab can
///   show one document (#140). Bound to the tab routing chose, or to the next tab to
///   register; when that tab closes, or no tab registers but one is open when the
///   index arrives, it goes to the tab in use, and with none open, to the next tab to
///   register.
public struct SceneRegistry<Scene: AnyObject> {
  /// A link handed to a tab: open it there, and when `bringsForward`, make that the
  /// tab in use and bring its window forward.
  public struct Delivery {
    public let link: RFCLink
    public let scene: Scene
    /// False for a tab opened behind the one in use, which stays behind.
    public let bringsForward: Bool
  }

  /// What to do with a link routed from outside.
  public enum Decision {
    /// Open it in this tab now.
    case deliver(Delivery)
    /// There is no tab: open a window, whose tab will take the link when it registers.
    case openWindow
    /// The index has not arrived; the link is held, and `indexSettled(preferring:)`
    /// delivers it.
    case wait
  }

  private struct Weak {
    weak var scene: Scene?
  }

  /// A link for a tab being made: unbound until that tab registers.
  private struct ForNewTab {
    let link: RFCLink
    let bringsForward: Bool
    var scene: Weak?
  }

  /// Where a routed link that waits is to go.
  private enum RoutedTarget {
    case nextScene
    case scene(Weak)
    case inUse
  }

  /// A link routed from outside, waiting.
  private struct Routed {
    let link: RFCLink
    var target: RoutedTarget
  }

  private var scenes: [Weak] = []
  private var forNewTabs: [ForNewTab] = []
  private var routed: Routed?
  /// Whether the index has arrived, or failed to: a link then waits for nothing more
  /// than a tab.
  private var isIndexSettled = false

  public init() {}

  /// The open tabs, most recently used first.
  public var open: [Scene] { scenes.compactMap(\.scene) }

  /// A new tab, now the most recently used, and the link made for it, if one is and
  /// the index has arrived.
  public mutating func register(_ scene: Scene) -> Delivery? {
    promote(scene)
    if let waiting = forNewTabs.firstIndex(where: { $0.scene == nil }) {
      forNewTabs[waiting].scene = Weak(scene: scene)
      guard isIndexSettled else { return nil }
      let held = forNewTabs.remove(at: waiting)
      return Delivery(link: held.link, scene: scene, bringsForward: held.bringsForward)
    }
    guard let waiting = routed, case .nextScene = waiting.target else { return nil }
    routed?.target = .scene(Weak(scene: scene))
    guard isIndexSettled else { return nil }
    routed = nil
    return Delivery(link: waiting.link, scene: scene, bringsForward: true)
  }

  public mutating func unregister(_ scene: Scene) {
    scenes.removeAll { $0.scene == nil || $0.scene === scene }
    forNewTabs.removeAll { Self.isGone($0.scene, or: scene) }
    if case .scene(let bound)? = routed?.target, Self.isGone(bound, or: scene) {
      routed?.target = .inUse
    }
  }

  /// Makes `scene` the most recently used, which is where an untargeted link lands.
  public mutating func activate(_ scene: Scene) {
    guard scenes.first?.scene !== scene else { return }
    promote(scene)
  }

  /// Where `link` goes: the tab already showing its document, else the preferred tab,
  /// else the most recently used, as `LinkRouting` decides; a new window when no tab is
  /// open. Held instead while the index has not arrived.
  public mutating func route(
    _ link: RFCLink, showing: (Scene) -> DocumentID?,
    preferring isPreferred: (Scene) -> Bool = { _ in false }
  ) -> Decision {
    scenes.removeAll { $0.scene == nil }
    guard
      let target = LinkRouting.target(
        for: link.id, in: open, showing: showing, preferring: isPreferred)
    else {
      routed = Routed(link: link, target: .nextScene)
      return .openWindow
    }
    guard isIndexSettled else {
      routed = Routed(link: link, target: .scene(Weak(scene: target)))
      return .wait
    }
    return .deliver(Delivery(link: link, scene: target, bringsForward: true))
  }

  /// Holds `link` for the next tab to register that no other link is held for: one
  /// being made for it, in front or behind.
  public mutating func hold(_ link: RFCLink, bringsForward: Bool) {
    forNewTabs.append(ForNewTab(link: link, bringsForward: bringsForward, scene: nil))
  }

  /// The index has arrived, or failed to: every link held for it whose tab is there.
  /// A routed link whose tab has closed, or that waits for a tab while one is open,
  /// goes to the preferred tab, else the most recently used, else the next to register.
  public mutating func indexSettled(preferring isPreferred: (Scene) -> Bool = { _ in false })
    -> [Delivery]
  {
    isIndexSettled = true
    var deliveries: [Delivery] = []
    forNewTabs.removeAll { held in
      guard let scene = held.scene?.scene else { return false }
      deliveries.append(
        Delivery(link: held.link, scene: scene, bringsForward: held.bringsForward))
      return true
    }
    if let waiting = routed {
      var bound: Scene?
      if case .scene(let weak) = waiting.target { bound = weak.scene }
      if let scene = bound ?? open.first(where: isPreferred) ?? open.first {
        routed = nil
        deliveries.append(Delivery(link: waiting.link, scene: scene, bringsForward: true))
      } else {
        // No tab is left to take it: the next to register is the tab in use.
        routed?.target = .nextScene
      }
    }
    return deliveries
  }

  private static func isGone(_ bound: Weak?, or scene: Scene) -> Bool {
    guard let bound else { return false }
    return bound.scene == nil || bound.scene === scene
  }

  private mutating func promote(_ scene: Scene) {
    scenes.removeAll { $0.scene == nil || $0.scene === scene }
    scenes.insert(Weak(scene: scene), at: 0)
  }
}
