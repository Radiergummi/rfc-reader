import RFCKit
import RFCReaderKit
import Testing

/// The open tabs a link is routed through, and the links waiting for one (#137): held
/// until there is a tab to take them, and a BCP or STD link until the index has arrived
/// too, so it opens its first RFC rather than selecting the series itself (#241).
@Suite("Scene registry")
@MainActor
struct SceneRegistryTests {
  final class Tab {
    var selection: DocumentID?
    init(showing selection: DocumentID? = nil) { self.selection = selection }
  }

  private let bcp14 = RFCLink(id: DocumentID(series: .bcp, number: 14))
  private let rfc9110 = RFCLink(id: .rfc(9110))
  private let std97 = RFCLink(id: DocumentID(series: .std, number: 97))

  private func registry(ready: Bool = true) -> SceneRegistry<Tab> {
    var registry = SceneRegistry<Tab>()
    if ready { _ = registry.indexSettled() }
    return registry
  }

  @Test func `registered tabs are most recently used first, and activation promotes`() {
    var registry = registry()
    let first = Tab()
    let second = Tab()
    _ = registry.register(first)
    _ = registry.register(second)
    #expect(registry.open.map(ObjectIdentifier.init) == [second, first].map(ObjectIdentifier.init))
    registry.activate(first)
    #expect(registry.open.first === first)
    registry.unregister(first)
    #expect(registry.open.map(ObjectIdentifier.init) == [ObjectIdentifier(second)])
  }

  /// A tab that has gone away is not kept alive by the registry, nor routed to.
  @Test func `a released tab is not open`() {
    var registry = registry()
    do {
      let gone = Tab()
      _ = registry.register(gone)
    }
    #expect(registry.open.isEmpty)
  }

  @Test func `a link goes to the tab showing its document, else the most recent`() {
    var registry = registry()
    let showing = Tab(showing: .rfc(9110))
    let recent = Tab()
    _ = registry.register(showing)
    _ = registry.register(recent)
    #expect(route(rfc9110, in: &registry) == .deliver(Delivery(rfc9110, to: showing)))
    #expect(route(bcp14, in: &registry) == .deliver(Delivery(bcp14, to: recent)))
  }

  /// With no tab open, a window is opened for the link, and the tab it makes takes it,
  /// once.
  @Test func `with no tab, the link waits for the tab a new window makes`() {
    var registry = registry()
    #expect(route(rfc9110, in: &registry) == .openWindow)
    let made = Tab()
    #expect(registry.register(made).map(Delivery.init) == Delivery(rfc9110, to: made))
    #expect(registry.register(Tab()) == nil)
  }

  /// #241: on a cold launch the first tab registers before the index has arrived. The
  /// link waits for the index, so that `open` can resolve the series to its first RFC.
  @Test func `a series link on a cold launch waits for the index`() {
    var registry = registry(ready: false)
    #expect(route(bcp14, in: &registry) == .openWindow)
    let first = Tab()
    #expect(registry.register(first) == nil)
    #expect(registry.indexSettled().map(Delivery.init) == [Delivery(bcp14, to: first)])
    #expect(registry.indexSettled().isEmpty)
  }

  /// A series link waits while the index is on its way, a tab already open or not, and
  /// is delivered when it arrives, to the tab it would have gone to.
  @Test func `a series link routed before the index arrives is delivered when it does`() {
    var registry = registry(ready: false)
    let showing = Tab(showing: bcp14.id)
    let recent = Tab()
    _ = registry.register(showing)
    _ = registry.register(recent)
    #expect(route(bcp14, in: &registry) == .wait)
    #expect(route(std97, in: &registry) == .wait)
    #expect(registry.indexSettled().map(Delivery.init) == [Delivery(std97, to: recent)])
  }

  /// A plain RFC link needs no index to resolve, so it does not wait for one: not with a
  /// tab open, nor for the first tab a window makes.
  @Test func `a plain RFC link routed before the index arrives is delivered at once`() {
    var registry = registry(ready: false)
    #expect(route(rfc9110, in: &registry) == .openWindow)
    let first = Tab()
    #expect(registry.register(first).map(Delivery.init) == Delivery(rfc9110, to: first))
    #expect(route(rfc9110, in: &registry) == .deliver(Delivery(rfc9110, to: first)))
    #expect(registry.indexSettled().isEmpty)
  }

  /// One slot: a plain link delivered at once is the later ask, so a series link still
  /// waiting for the index does not land on top of it when the index arrives.
  @Test func `a plain RFC link delivered at once replaces a series link still waiting`() {
    var registry = registry(ready: false)
    let reading = Tab()
    _ = registry.register(reading)
    #expect(route(bcp14, in: &registry) == .wait)
    #expect(route(rfc9110, in: &registry) == .deliver(Delivery(rfc9110, to: reading)))
    #expect(registry.indexSettled().isEmpty)
  }

  /// #140: one slot, so of two links before the first tab the later wins. The first
  /// tab can show one document, and the later link is the more recent ask.
  @Test func `of two links before the first tab the later wins`() {
    var registry = registry(ready: false)
    _ = route(rfc9110, in: &registry)
    _ = route(bcp14, in: &registry)
    let first = Tab()
    _ = registry.register(first)
    #expect(registry.indexSettled().map(Delivery.init) == [Delivery(bcp14, to: first)])
  }

  /// A link for a new tab goes to the next tab to register, and does not bring it
  /// forward: a tab opened behind stays behind.
  @Test func `a link held for a new tab goes to it, in the background as asked`() {
    var registry = registry()
    _ = registry.register(Tab())
    registry.hold(rfc9110, bringsForward: false)
    let made = Tab()
    let delivery = registry.register(made)
    #expect(delivery?.scene === made)
    #expect(delivery?.bringsForward == false)
  }

  /// A plain RFC link held for a new tab goes to it as it registers, index or not.
  @Test func `a plain RFC link held for a new tab does not wait for the index`() {
    var registry = registry(ready: false)
    _ = registry.register(Tab())
    registry.hold(rfc9110, bringsForward: true)
    let made = Tab()
    #expect(registry.register(made).map(Delivery.init) == Delivery(rfc9110, to: made))
    #expect(registry.indexSettled().isEmpty)
  }

  /// A series link held for a new tab waits for the index, then goes to that tab (#241).
  @Test func `a series link held for a new tab waits for the index`() {
    var registry = registry(ready: false)
    _ = registry.register(Tab())
    registry.hold(bcp14, bringsForward: true)
    let made = Tab()
    #expect(registry.register(made) == nil)
    #expect(registry.indexSettled().map(Delivery.init) == [Delivery(bcp14, to: made)])
  }

  /// Two kinds of waiting link do not displace each other: a tab opened behind while
  /// the index loads keeps its link when a link arrives from outside.
  @Test func `a new tab's link and a routed link both arrive`() {
    var registry = registry(ready: false)
    let reading = Tab()
    _ = registry.register(reading)
    registry.hold(std97, bringsForward: false)
    let behind = Tab()
    _ = registry.register(behind)
    registry.activate(reading)
    #expect(route(bcp14, in: &registry) == .wait)
    let delivered = registry.indexSettled().map(Delivery.init)
    #expect(
      delivered == [
        Delivery(std97, to: behind, bringsForward: false), Delivery(bcp14, to: reading),
      ])
  }

  /// A new tab's link whose tab closed before it was delivered is dropped: the tab in
  /// use did not ask for it.
  @Test func `a new tab's link whose tab closed is dropped`() {
    var registry = registry(ready: false)
    let reading = Tab()
    _ = registry.register(reading)
    registry.hold(bcp14, bringsForward: false)
    do {
      let behind = Tab()
      _ = registry.register(behind)
      registry.unregister(behind)
    }
    #expect(registry.indexSettled().isEmpty)
  }

  /// A routed link whose tab closed before the index arrived goes to the tab in use:
  /// the preferred one (#277), not merely the most recent.
  @Test func `a routed link whose tab closed goes to the preferred tab`() {
    var registry = registry(ready: false)
    let preferred = Tab()
    let other = Tab()
    _ = registry.register(preferred)
    _ = registry.register(other)
    do {
      let closing = Tab()
      _ = registry.register(closing)
      _ = route(bcp14, in: &registry)
      registry.unregister(closing)
    }
    let delivered = registry.indexSettled(preferring: { $0 === preferred })
    #expect(delivered.map(Delivery.init) == [Delivery(bcp14, to: preferred)])
  }

  /// A routed link whose tab closed, with no other tab open when the index arrived, goes
  /// to the next tab to register, not to whatever tab is in front at the next settle.
  @Test func `a routed link whose tab closed with none left goes to the next tab`() {
    var registry = registry(ready: false)
    do {
      let closing = Tab()
      _ = registry.register(closing)
      #expect(route(bcp14, in: &registry) == .wait)
      registry.unregister(closing)
    }
    #expect(registry.indexSettled().isEmpty)
    let made = Tab()
    #expect(registry.register(made).map(Delivery.init) == Delivery(bcp14, to: made))
    #expect(registry.indexSettled().isEmpty)
  }

  // MARK: - Support

  /// What a decision came to, comparable: the link and the tab, by identity.
  struct Delivery: Equatable {
    let link: RFCLink
    let scene: ObjectIdentifier
    let bringsForward: Bool

    init(_ link: RFCLink, to scene: Tab, bringsForward: Bool = true) {
      self.link = link
      self.scene = ObjectIdentifier(scene)
      self.bringsForward = bringsForward
    }

    init(_ delivery: SceneRegistry<Tab>.Delivery) {
      link = delivery.link
      scene = ObjectIdentifier(delivery.scene)
      bringsForward = delivery.bringsForward
    }
  }

  enum Decision: Equatable {
    case deliver(Delivery)
    case openWindow
    case wait
  }

  private func route(_ link: RFCLink, in registry: inout SceneRegistry<Tab>) -> Decision {
    switch registry.route(link, showing: \.selection) {
    case .deliver(let delivery): .deliver(Delivery(delivery))
    case .openWindow: .openWindow
    case .wait: .wait
    }
  }
}
