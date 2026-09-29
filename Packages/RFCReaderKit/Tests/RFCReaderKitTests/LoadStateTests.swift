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
    #expect(state.buildDelay == .zero)
  }

  /// A rebuild costs the whole document again, so a font-size slider or a window
  /// edge being dragged waits for the change to settle.
  @Test func `a rebuild of a document on screen waits for the change to settle`() {
    var state = LoadState()
    state.finish(document)
    state.install(built())
    #expect(state.buildDelay == .milliseconds(650))
  }
}
