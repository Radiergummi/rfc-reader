import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Reading path")
struct ReadingPathTests {
  /// A citation graph by hand: each RFC's normative references, in citation order.
  private struct Graph {
    var normative: [Int: [Int]]
    var undeclared: Set<Int> = []

    func references(of id: DocumentID) -> ReadingPath.References {
      ReadingPath.References(
        normative: (normative[id.number] ?? []).map(DocumentID.rfc),
        isUndeclared: undeclared.contains(id.number))
    }

    func walk(
      from root: Int, depth: Int = ReadingPath.defaultDepth, assumed: Set<Int> = []
    ) -> ReadingPath {
      ReadingPath.walk(
        from: .rfc(root), depth: depth, assumed: Set(assumed.map(DocumentID.rfc)),
        references: references(of:))
    }
  }

  private func numbers(_ path: ReadingPath) -> [Int] { path.steps.map(\.document.number) }

  @Test func `each document comes after the ones it depends on`() {
    let graph = Graph(normative: [1: [2, 3], 2: [4], 3: [4]])
    #expect(numbers(graph.walk(from: 1)) == [4, 2, 3, 1])
  }

  @Test func `a document without normative references is a path of itself`() {
    let path = Graph(normative: [:]).walk(from: 1)
    #expect(numbers(path) == [1])
    #expect(path.assumed.isEmpty)
    #expect(!path.isCut)
  }

  @Test func `a step's depth is its shortest distance from the root`() {
    // 4 is reached through 2 and 3 at depth 3 first in citation order, and directly at 1.
    let graph = Graph(normative: [1: [2, 4], 2: [3], 3: [4]])
    let path = graph.walk(from: 1)
    #expect(numbers(path) == [4, 3, 2, 1])
    #expect(path.steps.map(\.depth) == [1, 2, 1, 0])
  }

  @Test func `a cycle is broken by citation order`() {
    // 2 and 3 cite each other; 2 is cited first, so it is entered first and 3, which
    // it depends on, comes before it.
    let graph = Graph(normative: [1: [2, 3], 2: [3], 3: [2]])
    #expect(numbers(graph.walk(from: 1)) == [3, 2, 1])
  }

  @Test func `a citation of the root does not put it on the path twice`() {
    let graph = Graph(normative: [1: [2], 2: [1]])
    #expect(numbers(graph.walk(from: 1)) == [2, 1])
  }

  @Test func `assumed documents are listed once apart and not followed`() {
    let graph = Graph(normative: [1: [2, 9], 2: [9, 3], 9: [5]])
    let path = graph.walk(from: 1, assumed: [9])
    #expect(numbers(path) == [3, 2, 1])
    #expect(path.assumed == [.rfc(9)])
  }

  @Test func `an assumed root is still walked`() {
    let graph = Graph(normative: [9: [5]])
    #expect(numbers(graph.walk(from: 9, assumed: [9])) == [5, 9])
  }

  @Test func `the walk stops at the depth and says it was cut`() {
    let graph = Graph(normative: [1: [2], 2: [3], 3: [4]])
    let path = graph.walk(from: 1, depth: 2)
    #expect(numbers(path) == [3, 2, 1])
    #expect(path.isCut)
  }

  @Test func `a walk that reaches every document is not cut`() {
    let graph = Graph(normative: [1: [2], 2: [3]])
    #expect(!graph.walk(from: 1, depth: 2).isCut)
  }

  /// A reference at the depth that is already on the path, or assumed, leaves
  /// nothing out.
  @Test func `references already on the path do not cut it`() {
    let graph = Graph(normative: [1: [2, 3, 9], 2: [3], 3: [1, 9]])
    #expect(!graph.walk(from: 1, depth: 1, assumed: [9]).isCut)
  }

  @Test func `documents that declare no kind of reference are named`() {
    let graph = Graph(normative: [1: [2], 2: [3]], undeclared: [3, 7])
    #expect(graph.walk(from: 1).undeclared == [.rfc(3)])
  }

  @Test func `the assumed documents come first in the saved order`() {
    let path = Graph(normative: [1: [9, 2]]).walk(from: 1, assumed: [9])
    #expect(path.documents == [.rfc(9), .rfc(2), .rfc(1)])
    #expect(path.collectionName == "Reading Path: RFC 1")
  }

  @Test func `a row says what the index and the reading positions know`() {
    let path = Graph(normative: [1: [9, 2]]).walk(from: 1, assumed: [9])
    let index = [
      RFCMetadata(
        id: .rfc(2), title: "Two", date: PublicationDate(year: 1990), obsoletedBy: [.rfc(3)]),
      RFCMetadata(id: .rfc(9), title: "Nine", date: PublicationDate(year: 1990)),
    ]
    let rows = path.rows(
      metadata: { id in index.first { $0.id == id } }, isRead: { $0 == .rfc(9) })
    #expect(
      rows.assumed == [.init(document: .rfc(9), title: "Nine", obsoletedBy: [], isRead: true)])
    #expect(
      rows.steps == [
        .init(document: .rfc(2), title: "Two", obsoletedBy: [.rfc(3)], isRead: false),
        .init(document: .rfc(1), title: nil, obsoletedBy: [], isRead: false),
      ])
  }
}
