import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Where the reader is with a document (#135): loading it, showing it, or failed to
/// load it. One value rather than four optionals, so a document on screen beside an
/// error, or a build without its document, cannot be written down.
@Suite("Load state")
struct LoadStateTests {
  private struct Offline: Error {}

  private let document = Fixtures.document(.paragraph(Paragraph([.text("Body")])))

  private func built() -> BuiltDocument {
    DocumentTextBuilder.build(document, style: ReadingStyle())
  }

  @Test func `a reader starts loading`() {
    let state = LoadState()
    #expect(state.isLoading)
    #expect(state.document == nil)
    #expect(state.built == nil)
    #expect(state.failure == nil)
  }

  @Test func `a fetched document is shown before it is built`() {
    var state = LoadState()
    state.finish(document)
    #expect(state.document?.header.title == "T")
    #expect(state.built == nil)
    #expect(!state.isLoading)
  }

  @Test func `a build is installed over the document it was made from`() {
    var state = LoadState()
    state.finish(document)
    let first = built()
    state.install(first)
    #expect(state.built?.text === first.text)
    let second = built()
    state.install(second)
    #expect(state.built?.text === second.text)
    #expect(state.document?.header.title == "T")
  }

  /// There is nothing to install a build over.
  @Test func `a build without a document is dropped`() {
    var state = LoadState()
    state.install(built())
    #expect(state.isLoading)
    state.fail(Offline())
    state.install(built())
    #expect(state.built == nil)
    #expect(state.failure != nil)
  }

  @Test func `a failed load keeps its error, and trying again loads`() {
    var state = LoadState()
    state.fail(Offline())
    #expect(state.failure?.error is Offline)
    #expect(state.document == nil)
    state.begin()
    #expect(state.isLoading)
    #expect(state.failure == nil)
  }

  /// A document on screen is not replaced by the answer to a fetch nobody asked
  /// for again.
  @Test func `a document on screen is neither failed nor fetched over`() {
    var state = LoadState()
    state.finish(document)
    state.fail(Offline())
    #expect(state.failure == nil)
    state.finish(Fixtures.document(.paragraph(Paragraph([.text("Other")]))))
    #expect(state.document?.sections.first?.blocks == document.sections.first?.blocks)
  }

  // MARK: - When a build runs

  /// Nothing is on screen to disturb, and the column is already known, so the first
  /// build is built once and built right.
  @Test func `the first build of a document runs at once`() {
    var state = LoadState()
    state.finish(document)
    #expect(state.buildDelay(for: .live) == .zero)
    #expect(state.buildDelay(for: .discrete) == .zero)
    #expect(state.buildDelay(for: .none) == .zero)
  }

  /// A rebuild costs the whole document again, so a window edge being dragged
  /// waits for the column to settle.
  @Test func `a column still being dragged waits for the change to settle`() {
    var state = LoadState()
    state.finish(document)
    state.install(built())
    #expect(state.buildDelay(for: .live) == .milliseconds(650))
  }

  /// A rotation is one change with nothing to settle: waiting for it left artwork
  /// at the old column's width for a second after the text had reflowed.
  @Test func `a column that changed in one step builds at once`() {
    var state = LoadState()
    state.finish(document)
    state.install(built())
    #expect(state.buildDelay(for: .discrete) == .zero)
  }

  /// View ▸ Bigger and Smaller (#153) are a step at a time, and a step that
  /// waited 650 ms before it even started building read as a slow app.
  @Test func `a restyle of a document on screen runs at once`() {
    var state = LoadState()
    state.finish(document)
    state.install(built())
    #expect(state.buildDelay(for: .none) == .zero)
  }

  // MARK: - How the column changed

  @Test func `the same column is no change, live or not`() {
    #expect(ColumnChange(from: 400, to: 400, isLive: true) == .none)
    #expect(ColumnChange(from: 400, to: 400, isLive: false) == .none)
  }

  @Test func `a new column is live only while a resize is under way`() {
    #expect(ColumnChange(from: 400, to: 640, isLive: true) == .live)
    #expect(ColumnChange(from: 400, to: 640, isLive: false) == .discrete)
  }

  /// Nothing on screen was built for a column yet, so there is nothing to settle.
  @Test func `the first column is a change in one step`() {
    #expect(ColumnChange(from: nil, to: 400, isLive: true) == .discrete)
  }

  // MARK: - Whether the reader says it is loading (#263)

  /// A document from the cache normally builds before the delay is up, and slides
  /// in with its text rather than after a flash of progress.
  @Test func `a reader says nothing about loading before the delay`() {
    var state = LoadState()
    #expect(!state.showsProgress(isDue: false))
    state.finish(document)
    #expect(!state.showsProgress(isDue: false))
  }

  @Test func `a reader with nothing to show says it is loading once the delay is up`() {
    var state = LoadState()
    #expect(state.showsProgress(isDue: true))
    state.finish(document)
    #expect(state.showsProgress(isDue: true), "fetched and not yet built")
  }

  @Test func `a built document or a failure is shown instead`() {
    var built = LoadState()
    built.finish(document)
    built.install(self.built())
    #expect(!built.showsProgress(isDue: true))

    var failed = LoadState()
    failed.fail(Offline())
    #expect(!failed.showsProgress(isDue: true))
  }

  // MARK: - Whether a build runs

  @Test func `inputs nothing was built for start a build`() {
    #expect(BuildRequest.decide(17, built: nil, building: nil) == .start)
    #expect(BuildRequest.decide(18, built: 17, building: nil) == .start)
  }

  /// The pending build is for inputs that no longer hold, so it goes.
  @Test func `new inputs replace the build under way`() {
    #expect(BuildRequest.decide(19, built: 17, building: 18) == .start)
  }

  /// Appearing again asks with nothing changed: the build under way stands rather
  /// than being canceled and paid for twice.
  @Test func `the inputs of the build under way leave it to finish`() {
    #expect(BuildRequest.decide(18, built: 17, building: 18) == .keep)
  }

  @Test func `the inputs on screen with nothing under way build nothing`() {
    #expect(BuildRequest.decide(17, built: 17, building: nil) == .keep)
  }

  /// A slider dragged to 18 and back to 17 before the 18 build lands: the screen
  /// already shows 17, and the 18 build would put the wrong size over it.
  @Test func `coming back to the inputs on screen cancels the build under way`() {
    #expect(BuildRequest.decide(17, built: 17, building: 18) == .cancel)
  }
}
