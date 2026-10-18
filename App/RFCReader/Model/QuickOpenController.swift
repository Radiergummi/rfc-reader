import Foundation
import Observation
import RFCKit
import RFCReaderKit

/// The Mac's Go to RFC palette's glue, which keeps only its layout (#769): what is
/// typed, its exact resolution and the search for it, and opening what was chosen.
/// iOS's sheet shared it until it came to take an RFC number alone, which needs
/// none of it (#579).
@MainActor
@Observable
final class QuickOpenController {
  private let library: LibraryModel
  private let navigation: NavigationModel
  private let dismiss: () -> Void

  private(set) var input = ""
  private(set) var results = QuickOpenResults()
  /// Set by the first thing that closes the view. The search goes on through a
  /// dismiss animation, and a ↵ it was holding must not open a second document
  /// after Cancel or a chosen row.
  private var isClosing = false

  init(library: LibraryModel, navigation: NavigationModel, dismiss: @escaping () -> Void) {
    self.library = library
    self.navigation = navigation
    self.dismiss = dismiss
  }

  /// What is typed, less the spaces around it, which change nothing it finds.
  var query: String { input.normalizedQuery }

  /// What the view says in place of rows, if anything.
  var message: String? { results.message(indexState: library.indexState) }

  /// What a search depends on. The index is part of it so that a view opened before
  /// the index loaded searches again once it has.
  struct SearchKey: Equatable {
    var query: String
    var hasIndex: Bool
  }

  var searchKey: SearchKey { SearchKey(query: query, hasIndex: library.index != nil) }

  /// Takes what was typed, and resolves it on the keystroke itself, before any ↵
  /// queued behind it can read the selection: an `onChange` or the search's task
  /// would only run a turn later.
  func type(_ text: String) {
    input = text
    resolve()
  }

  /// What was typed, resolved exactly: again once the index loads, so a series
  /// typed before it is listed as its members.
  func resolve() {
    let exact = DocumentReference.link(from: query)
    let members = exact.flatMap { library.index?.series($0.id)?.members } ?? []
    results.show(
      query: query, exact: exact, members: members,
      registry: library.registryMatches(for: query),
      isObsolete: { [library] in library.metadata($0)?.isObsolete ?? false })
  }

  /// Searches for what is typed, and opens what a ↵ held while it ran asked for.
  func search() async {
    let query = query
    guard let hits = await library.quickOpenHits(for: query) else { return }
    if let opening = results.show(hits: hits, for: query) {
      open(opening.link, activation: opening.activation)
    }
  }

  func moveSelection(by offset: Int) {
    results.moveSelection(by: offset)
  }

  /// Return and Open: the selected row, or the one the search still running selects.
  func openSelection() {
    if let opening = results.activate(.current) {
      open(opening.link, activation: opening.activation)
    }
  }

  func open(_ link: RFCLink, activation: LinkActivation = .current) {
    guard !isClosing else { return }
    library.open(link, activation: activation, in: navigation)
    close()
  }

  func close() {
    isClosing = true
    dismiss()
  }
}
