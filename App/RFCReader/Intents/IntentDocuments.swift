import AppIntents
import RFCKit
import RFCReaderKit

/// Why an intent could not answer, in the words Siri and Shortcuts show (#192).
nonisolated enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
  /// The index has not loaded, and could not be fetched.
  case indexUnavailable
  /// The document is neither cached nor in an installed pack, and there is no
  /// connection to fetch it over.
  case notAvailableOffline(DocumentID)
  /// The document did not load for another reason, which `reason` gives.
  case notLoaded(DocumentID, reason: String)
  /// The section is not in the document, which has changed since it was chosen.
  case noSuchSection(SectionIdentifier)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .indexUnavailable:
      "The RFC index isn't available. Open RFC Reader to load it, then try again."
    case .notAvailableOffline(let id):
      "\(id.displayName) isn't available offline. Connect to the internet, or keep it offline in RFC Reader, then try again."
    case .notLoaded(let id, let reason):
      "\(id.displayName) didn't load: \(reason)"
    case .noSuchSection(let identifier):
      "\(identifier.document.displayName) has no section \(identifier.anchor)."
    }
  }
}

/// The documents intents read their sections and requirements from (#192).
nonisolated enum IntentDocuments {
  /// `id`, loaded as opening it loads it: from memory, the cache or an installed
  /// pack, and otherwise from the network. Offline without it, that is what the
  /// intent says, rather than finding nothing in it.
  static func load(_ id: DocumentID) async throws -> RFCDocument {
    // The index says which formats the document has, which decides what is fetched.
    guard await LibraryModel.shared.settledSearch() != nil else {
      throw IntentFailure.indexUnavailable
    }
    do {
      return try await LibraryModel.shared.document(for: id)
    } catch {
      let failure = LoadFailure(error: error)
      if [.offline, .cellularDenied].contains(failure.kind) {
        throw IntentFailure.notAvailableOffline(id)
      }
      throw IntentFailure.notLoaded(id, reason: failure.message)
    }
  }
}
