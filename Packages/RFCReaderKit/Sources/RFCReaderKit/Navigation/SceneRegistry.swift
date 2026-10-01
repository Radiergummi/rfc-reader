import RFCKit

/// The open tabs a link is routed through, most recently used first, and the one link
/// waiting for a tab (#137). Pure, over any kind of tab, so the routing is tested here
/// rather than in the App target, which carries out its decisions.
///
/// One place decides, because `onOpenURL` is delivered to every open scene: without
/// it, a deep link would open in all of them at once. Tabs are held weakly: a tab's
/// lifetime is its window's, and nothing here should keep a closed one alive.
///
/// A link waits, in one slot, until there is a tab to take it and the index has
/// arrived (#241). On a cold launch the first tab registers before the index is
/// loaded, and a BCP or STD link handed over then would select the series itself,
/// because resolving it to its first RFC needs the index. Every link waits, not only
/// a series': the wait is the moment the cached index takes to read, and one rule is
/// easier to trust than two. Of two links that wait, the later wins: the first tab
/// can show one document, and the later link is the more recent ask.
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
    /// The index has not arrived; the link is held, and `indexSettled()` delivers it.
    case wait
  }

  private struct Weak {
    weak var scene: Scene?
  }

  private enum Target {
    /// The next tab to register: one being made for the link.
    case nextScene
    /// This tab, as routing chose it.
    case scene(Weak)
    /// The tab it was bound to has closed: the tab in use, when the link is delivered.
    case inUse
  }

  private struct Pending {
    let link: RFCLink
    var target: Target
    let bringsForward: Bool
  }

  private var scenes: [Weak] = []
  private var pending: Pending?
  /// Whether the index has arrived, or failed to: a link then waits for nothing more
  /// than a tab.
  public private(set) var isIndexSettled = false

  public init() {}

  /// The open tabs, most recently used first.
  public var open: [Scene] { scenes.compactMap(\.scene) }

  /// A new tab, now the most recently used, and the link it is to take, if one waits
  /// for it and may be delivered.
  public mutating func register(_ scene: Scene) -> Delivery? {
    promote(scene)
    guard var waiting = pending else { return nil }
    if case .nextScene = waiting.target {
      waiting.target = .scene(Weak(scene: scene))
      pending = waiting
    }
    return deliverIfReady()
  }

  public mutating func unregister(_ scene: Scene) {
    scenes.removeAll { $0.scene == nil || $0.scene === scene }
    if case .scene(let bound)? = pending?.target, bound.scene == nil || bound.scene === scene {
      pending?.target = .inUse
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
      pending = Pending(link: link, target: .nextScene, bringsForward: true)
      return .openWindow
    }
    guard isIndexSettled else {
      pending = Pending(link: link, target: .scene(Weak(scene: target)), bringsForward: true)
      return .wait
    }
    return .deliver(Delivery(link: link, scene: target, bringsForward: true))
  }

  /// Holds `link` for the next tab to register: one being made for it, in front or
  /// behind.
  public mutating func hold(_ link: RFCLink, bringsForward: Bool) {
    pending = Pending(link: link, target: .nextScene, bringsForward: bringsForward)
  }

  /// The index has arrived, or failed to: the link held for it, if its tab is there.
  public mutating func indexSettled() -> Delivery? {
    isIndexSettled = true
    return deliverIfReady()
  }

  private mutating func deliverIfReady() -> Delivery? {
    guard isIndexSettled, let waiting = pending else { return nil }
    let scene: Scene?
    switch waiting.target {
    case .nextScene: scene = nil
    case .scene(let bound): scene = bound.scene ?? open.first
    case .inUse: scene = open.first
    }
    guard let scene else { return nil }
    pending = nil
    return Delivery(link: waiting.link, scene: scene, bringsForward: waiting.bringsForward)
  }

  private mutating func promote(_ scene: Scene) {
    scenes.removeAll { $0.scene == nil || $0.scene === scene }
    scenes.insert(Weak(scene: scene), at: 0)
  }
}
