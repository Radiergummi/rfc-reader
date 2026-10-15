import CoreGraphics
import Testing

@testable import RFCReaderKit

@MainActor
@Suite("Reader controller")
struct ReaderControllerTests {
  /// A text view's coordinator that records what it was asked.
  private final class FakeDriver: ReaderTextDriving {
    var isInstalled = false
    var scrolls: [ReaderController.ScrollTarget] = []
    var headingMoves = 0

    func scroll(to anchor: String, offset: Int) {
      scrolls.append(ReaderController.ScrollTarget(anchor: anchor, offset: offset))
    }

    func headingDidMove() {
      headingMoves += 1
    }
  }

  /// Sections one per hundred characters, from 50: the first fifty characters are
  /// ahead of section one, as an abstract is.
  private static let sections = AnchorIndex(
    (1...3).map {
      AnchorIndex.Entry(anchor: "section-\($0)", offset: $0 * 100 - 50, heading: "\($0).")
    })

  private let controller = ReaderController()
  private let driver = FakeDriver()

  init() {
    controller.driver = driver
  }

  /// Lets the hop land: a task made on the main actor runs after the ones before it.
  private func hop() async {
    await Task {}.value
  }

  // MARK: - Place and section

  @Test func `the place and the anchor are there before the hop lands`() async {
    let place = ReadingPlace(anchor: "section-2", offset: 10)
    controller.reportPlace(place, line: 160, in: Self.sections)

    #expect(controller.place == place)
    #expect(controller.anchor == "section-2")
    #expect(controller.section == nil)
    await hop()
    #expect(controller.section == "section-2")
  }

  @Test func `a move of the place is told at once, and only a move`() {
    var told = 0
    controller.placeDidChange = { told += 1 }
    let place = ReadingPlace(anchor: "section-1", offset: 3)

    controller.reportPlace(place, line: 53, in: Self.sections)
    controller.reportPlace(place, line: 53, in: Self.sections)

    #expect(told == 1)
  }

  @Test func `the abstract reports section one, ahead of the sections`() async {
    controller.reportPlace(nil, line: 10, in: Self.sections)

    #expect(controller.anchor == "section-1")
    #expect(controller.isAheadOfSections)
    controller.reportPlace(nil, line: 60, in: Self.sections)
    #expect(!controller.isAheadOfSections)
  }

  @Test func `a section is published as the reader crosses into it`() async {
    controller.reportPlace(nil, line: 60, in: Self.sections)
    controller.reportPlace(nil, line: 70, in: Self.sections)
    await hop()
    #expect(controller.section == "section-1")

    controller.reportPlace(nil, line: 160, in: Self.sections)
    await hop()
    #expect(controller.section == "section-2")
  }

  @Test func `a document without sections reports none`() async {
    controller.reportPlace(nil, line: 10, in: AnchorIndex([]))
    await hop()

    #expect(controller.anchor == nil)
    #expect(controller.section == nil)
    #expect(controller.isAheadOfSections)
  }

  // MARK: - Scroll requests

  @Test func `a scroll asked for before the install is carried out once, after it`() {
    controller.scroll(to: "section-2", offset: 4)

    #expect(driver.scrolls.isEmpty)
    #expect(controller.pendingTarget?.anchor == "section-2")
    driver.isInstalled = true
    #expect(controller.takePendingTarget() == .init(anchor: "section-2", offset: 4))
    #expect(controller.takePendingTarget() == nil)
  }

  @Test func `the install that carried out a scroll says so once, to its own arrival`() {
    controller.scroll(to: "section-2")
    driver.isInstalled = true
    _ = controller.takePendingTarget()

    #expect(controller.takeInstallCarriedOutTarget())
    #expect(!controller.takeInstallCarriedOutTarget())

    // A text view made again arrives afresh, whatever the last one's install did.
    controller.scroll(to: "section-3")
    controller.driver = nil
    _ = controller.takePendingTarget()
    let next = FakeDriver()
    controller.driver = next
    #expect(!controller.takeInstallCarriedOutTarget())
  }

  @Test func `a scroll asked for with a build installed goes to it at once`() {
    driver.isInstalled = true

    controller.scroll(to: "section-3")

    #expect(driver.scrolls == [.init(anchor: "section-3")])
    #expect(controller.pendingTarget == nil)
    #expect(controller.takePendingTarget() == nil)
  }

  @Test func `a scroll asked for with no text view waits for one`() {
    controller.driver = nil

    controller.scroll(to: "section-1")

    #expect(controller.pendingTarget?.anchor == "section-1")
  }

  // MARK: - Title and heading

  @Test func `the title is passed on at once, with its reader`() {
    let reader = FakeDriver()
    var reports: [(ToolbarTitleState, ObjectIdentifier)] = []
    var releases: [ObjectIdentifier] = []
    controller.titleSink = .init(
      report: { reports.append(($0, ObjectIdentifier($1))) },
      release: { releases.append(ObjectIdentifier($0)) })

    controller.reportTitle(.shown, from: reader)
    controller.releaseTitle(from: reader)

    #expect(reports.map(\.0) == [.shown])
    #expect(reports.map(\.1) == [ObjectIdentifier(reader)])
    #expect(releases == [ObjectIdentifier(reader)])
  }

  @Test func `a sink set after the report is told the last title`() {
    let reader = FakeDriver()
    controller.reportTitle(.hidden, from: reader)
    var reports: [ToolbarTitleState] = []

    controller.titleSink = .init(report: { state, _ in reports.append(state) }, release: { _ in })

    #expect(reports == [.hidden])
  }

  @Test func `a released title is not told to a sink set after`() {
    let reader = FakeDriver()
    controller.reportTitle(.hidden, from: reader)
    controller.releaseTitle(from: reader)
    var reports: [ToolbarTitleState] = []

    controller.titleSink = .init(report: { state, _ in reports.append(state) }, release: { _ in })

    #expect(reports.isEmpty)
  }

  @Test func `a moved heading is told to the text view`() {
    controller.headingBottom = 40
    controller.headingBottom = 40
    controller.headingBottom = 52

    #expect(driver.headingMoves == 2)
  }

  // MARK: - Selection, bars and folding

  @Test func `the selection is published after the hop, once per change`() async {
    controller.reportSelection(true)
    #expect(!controller.hasSelection)
    await hop()
    #expect(controller.hasSelection)

    controller.reportSelection(false)
    await hop()
    #expect(!controller.hasSelection)
  }

  @Test func `the bars are published after the hop`() async {
    controller.reportBars(hidden: true)
    #expect(!controller.barsHidden)
    await hop()
    #expect(controller.barsHidden)
  }

  @Test func `a folding asked for is taken once`() async {
    let folding = Folding(mode: .outline, expanded: ["section-1"])
    controller.requestFolding(folding)
    #expect(controller.takeFolding() == nil)
    await hop()

    #expect(controller.takeFolding() == folding)
    #expect(controller.takeFolding() == nil)
  }
}
