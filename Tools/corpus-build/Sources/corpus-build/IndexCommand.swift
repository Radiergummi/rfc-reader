import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// Writes the corpus's index database (#174): what `IndexDatabase` holds, computed
/// over every document of the converted corpus, legacy and modern alike.
struct IndexCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "index",
    abstract: "Write the index database of the converted corpus."
  )

  private static let logger = Logger(command: "index")

  @Option(name: .customLong("in"), help: "The directory of rfcNNNN.xml files.")
  var input: String

  @Option(help: "Where to write the database.")
  var out: String

  @Option(help: "The data packs' version, such as 2026.09.")
  var version: String

  func run() throws {
    let corpus = try ConvertedCorpus(directory: URL(fileURLWithPath: input))
    Self.logger.info("reading", metadata: ["documents": "\(corpus.files.count)"])

    let clock = ContinuousClock()
    let started = clock.now
    let database = try IndexDatabase(creatingAt: URL(fileURLWithPath: out))
    try database.setMeta("version", to: version)
    var indexed = 0
    var citations = 0
    // Every document read, and what it obsoletes, for the second pass, which needs
    // the documents of an edge at once: holding every parsed document for it would
    // hold the corpus.
    var readFiles: [DocumentID: URL] = [:]
    var obsoletes: [DocumentID: [DocumentID]] = [:]
    let reading = try corpus.read { offset, file, id, document in
      let cited = Citations.of(document, citing: id)
      try database.insert(cited, citing: id)
      indexed += 1
      citations += cited.count
      readFiles[id] = file
      if !document.header.obsoletes.isEmpty {
        obsoletes[id] = document.header.obsoletes
      }
      if (offset + 1) % 2000 == 0 {
        Self.logger.info(
          "progress", metadata: ["completed": "\(offset + 1)", "total": "\(corpus.files.count)"])
      }
    }
    Self.logger.report(reading)

    // A section's best match is judged across every edge it is on, so the documents
    // joined by obsoletes edges are aligned a group at a time, each parsed once. An
    // obsoleted number the corpus does not hold, such as an RFC never issued, joins
    // no group; one that failed to parse is reported above.
    var successions = 0
    for group in Self.groups(of: obsoletes, among: Set(readFiles.keys)) {
      let documents = try group.compactMap { id in
        try readFiles[id].map { try Self.document(id, at: $0) }
      }
      let pairs = SectionAlignment.pairs(among: documents)
      try database.insert(pairs)
      successions += pairs.count
    }
    try database.setMeta("documents", to: String(indexed))
    try database.close()

    let size = try FileManager.default.attributesOfItem(atPath: out)[.size] as? Int ?? 0
    Self.logger.info(
      "wrote index",
      metadata: [
        "documents": "\(indexed)", "citations": "\(citations)",
        "successions": "\(successions)", "bytes": "\(size)",
        "duration": "\(clock.now - started)", "path": "\(out)",
      ])
    // An RFC left out is a gap in the graph nothing else would show, so the run fails
    // once the rest is written, for the files to be looked at.
    try Self.logger.failOnLeftOut(reading)
  }

  /// The documents joined by obsoletes edges between documents in `read`, a group for
  /// each connected set of two or more, in order.
  private static func groups(
    of obsoletes: [DocumentID: [DocumentID]], among read: Set<DocumentID>
  ) -> [[DocumentID]] {
    var parent: [DocumentID: DocumentID] = [:]
    func root(_ id: DocumentID) -> DocumentID {
      var current = id
      while let next = parent[current], next != current {
        current = next
      }
      return current
    }
    for (new, olds) in obsoletes {
      for old in olds where old != new && read.contains(old) {
        let (first, second) = (root(new), root(old))
        if first != second {
          parent[max(first, second)] = min(first, second)
        }
      }
    }
    let members = Dictionary(grouping: parent.keys.sorted() + Set(parent.values).sorted()) {
      root($0)
    }
    return members.keys.sorted().compactMap { key in
      let group = Set(members[key] ?? []).sorted()
      return group.count > 1 ? group : nil
    }
  }

  /// The document at `file`, as the one its file names, for the same reason the
  /// first pass takes that number: `SectionAlignment` writes it into each row.
  private static func document(_ id: DocumentID, at file: URL) throws -> RFCDocument {
    var document = try RFCXMLParser.parse(Data(contentsOf: file))
    document.header.id = id
    return document
  }
}
