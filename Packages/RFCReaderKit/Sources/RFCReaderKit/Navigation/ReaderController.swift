import CoreGraphics
import Foundation
import Observation

/// The reader's text view, as far as `ReaderController` drives it: its coordinator.
@MainActor
public protocol ReaderTextDriving: AnyObject {
  /// Whether a build is installed, which a scroll request can be carried out on.
  var isInstalled: Bool { get }
  /// Puts the anchor's line, `offset` characters past it, at the top of the viewport.
  func scroll(to anchor: String, offset: Int)
  /// The header's heading moved: the toolbar's title is worked out again.
  func headingDidMove()
}

/// Where the reader is, and what it was asked to do: the one interface between a
/// document's view and its text view (#598).
///
/// Owned by the view, which hands it to the text view's coordinator. What the
/// coordinator says goes in two halves:
///
/// - **At once**, outside observation: the place, the section's anchor, whether
///   the viewport is ahead of section one, the heading's bottom and the toolbar's
///   title. What reads these cannot wait: the reading position saved on the way out,
///   which comes before a hop would land, and a title coupled to the scroll.
/// - **After one hop**, observed: the section, the selection, the bars and a folding
///   for the scene. The coordinator reports from inside SwiftUI's update — installing
///   a build, jumping — where changing observed state is illegal, so `publish` moves
///   them to the next turn of the main actor.
///
/// Requests go the other way: `scroll(to:offset:)` reaches the text view at once
/// when it has a build installed, and waits for the install otherwise.
@MainActor @Observable
public final class ReaderController {
  /// Where a scroll request goes. A jump is never animated: the layout engine
  /// settles its line in several passes, each followed by a layout, so there is no
  /// single scroll to animate (#585).
  public struct ScrollTarget: Equatable, Sendable {
    public let anchor: String
    /// Characters past the anchor: a saved reading position's line (#322).
    public let offset: Int

    public init(anchor: String, offset: Int = 0) {
      self.anchor = anchor
      self.offset = offset
    }
  }

  /// Where the toolbar's title is told what the reader says of it; see
  /// `ToolbarTitleOwnership`. The reader is the coordinator, which owns what it
  /// reported until it releases it (#281): the last text view's teardown can come
  /// after the next one's report.
  public struct TitleSink {
    public let report: (ToolbarTitleState, _ reader: AnyObject) -> Void
    public let release: (_ reader: AnyObject) -> Void

    public init(
      report: @escaping (ToolbarTitleState, _ reader: AnyObject) -> Void,
      release: @escaping (_ reader: AnyObject) -> Void
    ) {
      self.report = report
      self.release = release
    }
  }

  // MARK: - At once

  /// The text view this drives, while it has one.
  @ObservationIgnored public weak var driver: (any ReaderTextDriving)? {
    didSet { if driver !== oldValue { installCarriedOutTarget = false } }
  }

  /// The reader's line, as a place that survives a rebuild: what the reading
  /// position saves (#322). Nil at the top of the document.
  @ObservationIgnored public private(set) var place: ReadingPlace? {
    didSet { if place != oldValue { placeDidChange() } }
  }
  /// Told when `place` moves, on every scroll tick that moves it: the view saves the
  /// place once the reader stops (#155).
  @ObservationIgnored public var placeDidChange: () -> Void = {}
  /// The anchor of the section the reader is in, as last reported; `section` is its
  /// observed copy, a hop behind.
  @ObservationIgnored public private(set) var anchor: String?
  /// Whether the top of the viewport is ahead of section one, which `anchor` reports
  /// as section one: a text view made again starts at the top, not there (#449).
  @ObservationIgnored public private(set) var isAheadOfSections = false
  /// Where the header's heading ends, in the hosted header's own coordinates, as
  /// the header measured it. The header is hosted outside SwiftUI's diffing and
  /// built once, so it writes here, and the text view works out the title again: it
  /// can report its viewport before the header has measured, and nothing scrolls
  /// afterwards to report it again.
  @ObservationIgnored public var headingBottom: CGFloat? {
    didSet { if headingBottom != oldValue { driver?.headingDidMove() } }
  }

  /// Where the title goes. Told the last title at once when set: the text view can
  /// report before the view has set it.
  @ObservationIgnored public var titleSink: TitleSink? {
    didSet {
      if let title, let reader = title.reader.reader { titleSink?.report(title.state, reader) }
    }
  }
  /// The last title and the coordinator it came from, weakly: the coordinator holds
  /// this controller, and with it the whole document.
  @ObservationIgnored private var title: (state: ToolbarTitleState, reader: WeakReader)?

  private struct WeakReader {
    weak var reader: AnyObject?
  }

  /// What the selection was last reported as, so a selection dragged across the text
  /// publishes once rather than on every character.
  @ObservationIgnored private var reportedSelection: Bool?

  /// A scroll asked for while no build was installed, carried out by the install;
  /// see `scroll(to:offset:)`.
  @ObservationIgnored public private(set) var pendingTarget: ScrollTarget?
  /// Whether the text view's install carried out a pending scroll; see
  /// `takeInstallCarriedOutTarget()`.
  @ObservationIgnored private var installCarriedOutTarget = false

  // MARK: - After one hop

  /// The section the reader is in: the contents' highlight.
  public private(set) var section: String?
  /// Whether the reader's text has a selection: Edit ▸ Copy as Quote is grayed out
  /// without one, as Copy is (#186). Reported on macOS only.
  public private(set) var hasSelection = false
  /// Whether reading on has put the bars away, on iPhone; see `ReaderChrome`.
  public private(set) var barsHidden = false
  /// A folding the text view changed itself — a jump into folded text, a heading
  /// toggled — for the scene to take (`takeFolding()`). A request rather than a
  /// value, so that the same folding asked for twice reaches the scene twice.
  public private(set) var foldingRequest: Folding?
  /// What became of each highlight of the document in the build on screen (#522):
  /// where it is, or why it is drawn nowhere. The Annotations tab lists it.
  public private(set) var highlightStatuses: [UUID: HighlightPlacement.Status] = [:]

  public init() {}

  // MARK: - Reports

  /// The reader's line moved to `line`, at `place`: the section it is in is reported
  /// at once, and published once it changed. The abstract and whatever else is
  /// ahead of section one report section one, with `isAheadOfSections` set.
  public func reportPlace(_ place: ReadingPlace?, line: Int, in sections: AnchorIndex) {
    self.place = place
    let section = sections.anchor(at: line)
    isAheadOfSections = section == nil
    // Once per section, not once per scroll tick.
    guard let anchor = section ?? sections.entries.first?.anchor, anchor != self.anchor
    else { return }
    self.anchor = anchor
    publish(.section(anchor))
  }

  public func reportSelection(_ hasSelection: Bool) {
    guard hasSelection != reportedSelection else { return }
    reportedSelection = hasSelection
    publish(.selection(hasSelection))
  }

  public func reportBars(hidden: Bool) {
    publish(.bars(hidden))
  }

  /// Where the build on screen placed the document's highlights.
  public func reportHighlights(_ statuses: [UUID: HighlightPlacement.Status]) {
    publish(.highlights(statuses))
  }

  /// The text view changed the folding itself, and the scene is to follow.
  public func requestFolding(_ folding: Folding) {
    publish(.folding(folding))
  }

  /// The folding the text view asked for, if it has asked since this was last called.
  public func takeFolding() -> Folding? {
    defer { if foldingRequest != nil { foldingRequest = nil } }
    return foldingRequest
  }

  /// Where the title is, from `reader`, passed on at once: it is coupled to the
  /// scroll, and a hop would leave it a frame behind the text.
  public func reportTitle(_ state: ToolbarTitleState, from reader: AnyObject) {
    title = (state, WeakReader(reader: reader))
    titleSink?.report(state, reader)
  }

  /// `reader` has gone, and what it said of the title goes with it.
  public func releaseTitle(from reader: AnyObject) {
    if title?.reader.reader === reader { title = nil }
    titleSink?.release(reader)
  }

  // MARK: - Requests

  /// Scrolls the reader to `anchor`: now, in the build the text view has installed,
  /// even with a rebuild on its way, which carries the place across as a resize
  /// does; or, with none installed, once one is (`takePendingTarget()`).
  public func scroll(to anchor: String, offset: Int = 0) {
    let target = ScrollTarget(anchor: anchor, offset: offset)
    guard let driver, driver.isInstalled else {
      pendingTarget = target
      return
    }
    pendingTarget = nil
    driver.scroll(to: target.anchor, offset: target.offset)
  }

  /// The scroll asked for before the install, for the text view to carry out after
  /// it; asked once, so it is carried out once.
  public func takePendingTarget() -> ScrollTarget? {
    defer { pendingTarget = nil }
    if pendingTarget != nil { installCarriedOutTarget = true }
    return pendingTarget
  }

  /// Whether the install of the text view on screen carried out a scroll asked for
  /// while there was none, such as a jump from the contents over the original text:
  /// that is where the text view arrives, and nothing else is to move it there.
  /// Answered once.
  public func takeInstallCarriedOutTarget() -> Bool {
    defer { installCarriedOutTarget = false }
    return installCarriedOutTarget
  }

  // MARK: - The hop

  private enum Report {
    case section(String)
    case selection(Bool)
    case bars(Bool)
    case folding(Folding)
    case highlights([UUID: HighlightPlacement.Status])
  }

  /// The one hop: what the coordinator reports from inside SwiftUI's update reaches
  /// observed state on the next turn of the main actor.
  private func publish(_ report: Report) {
    Task { self.apply(report) }
  }

  private func apply(_ report: Report) {
    switch report {
    case .section(let anchor): section = anchor
    case .selection(let hasSelection): self.hasSelection = hasSelection
    case .bars(let hidden): barsHidden = hidden
    case .folding(let folding): foldingRequest = folding
    case .highlights(let statuses):
      if statuses != highlightStatuses { highlightStatuses = statuses }
    }
  }
}
