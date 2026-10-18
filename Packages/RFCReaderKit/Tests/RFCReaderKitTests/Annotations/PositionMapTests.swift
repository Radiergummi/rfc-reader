import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The guard on the position map (#522): every storage character is mapped or the
/// storage's own, every model character is mapped or hidden in that build, never both
/// and never twice, a mapped character is the model's character, and model → storage
/// → model comes back. At two columns, so a table is set as a grid in one and stacked
/// in the other, and a folded block unfolded in one and as published in the other.
@Suite("Annotations: the position map")
struct PositionMapTests {
  static let fixtures = ["rfc8999.xml", "rfc2119.txt", "rfc9197.xml", "rfc9290.xml"]
  /// A phone's column and a wide Mac's.
  static let measures: [CGFloat] = [300, 900]

  @Test(arguments: fixtures, measures)
  func `every model character is mapped once or hidden`(fixture: String, measure: CGFloat) throws {
    let document = try Fixtures.document(named: fixture)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(measure: measure))
    let map = built.positions
    // How many times each model character is mapped, and hidden.
    var mapped = [Int](repeating: 0, count: map.model.length)
    var hidden = [Int](repeating: 0, count: map.model.length)
    for run in map.runs {
      for offset in run.model..<run.model + run.length { mapped[offset] += 1 }
    }
    for range in map.hidden {
      for offset in range { hidden[offset] += 1 }
    }
    let unaccounted = mapped.indices.filter { mapped[$0] + hidden[$0] == 0 }
    let twice = mapped.indices.filter { mapped[$0] + hidden[$0] > 1 }
    #expect(
      unaccounted.isEmpty,
      "\(fixture) at \(measure): \(unaccounted.count) model characters neither mapped nor hidden, first \(describe(unaccounted.first, in: map.model))"
    )
    #expect(
      twice.isEmpty,
      "\(fixture) at \(measure): \(twice.count) model characters mapped twice or mapped and hidden, first \(describe(twice.first, in: map.model))"
    )
  }

  @Test(arguments: fixtures, measures)
  func `a mapped character is the model's character`(fixture: String, measure: CGFloat) throws {
    let document = try Fixtures.document(named: fixture)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(measure: measure))
    let storage = built.text.string as NSString
    var mismatches = 0
    var first: String?
    for run in built.positions.runs {
      #expect(run.storage + run.length <= storage.length)
      for index in 0..<run.length
      where storage.character(at: run.storage + index)
        != built.positions.model.units[run.model + index]
      {
        mismatches += 1
        if first == nil {
          first = "storage \(run.storage + index) against model \(run.model + index)"
        }
      }
    }
    #expect(mismatches == 0, "\(fixture) at \(measure): \(mismatches) mismatches, first \(first ?? "")")
  }

  @Test(arguments: fixtures, measures)
  func `model to storage to model comes back`(fixture: String, measure: CGFloat) throws {
    let document = try Fixtures.document(named: fixture)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(measure: measure))
    let map = built.positions
    var failures = 0
    for offset in stride(from: 0, to: map.model.length, by: 7) {
      guard let storage = map.storageOffset(forModel: offset) else { continue }
      if map.modelOffset(forStorage: storage) != offset { failures += 1 }
    }
    #expect(failures == 0)
  }

  /// The model text a build hides is what the design says it may: joins and line
  /// breaks, a stacked table's header row, a folded block's header, a label an aside's
  /// caption replaced. At a wide column the fixtures set every table as a grid and
  /// have no folded block, so what is hidden there is white space and asides' labels.
  @Test(arguments: fixtures)
  func `a wide column hides white space alone`(fixture: String) throws {
    let document = try Fixtures.document(named: fixture)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(measure: 2000))
    let map = built.positions
    let hidden = map.hidden.map { map.model.text(in: $0) }
      .filter { !$0.allSatisfy(\.isWhitespace) }
      // An aside's label, which its caption replaced: RFC 9197 has one.
      .filter { !$0.lowercased().hasPrefix("note") }
    #expect(hidden.isEmpty, "\(fixture): \(hidden.prefix(5))")
  }

  private func describe(_ offset: Int?, in model: ModelText) -> String {
    guard let offset else { return "none" }
    let text = model.text(in: max(0, offset - 20)..<min(model.length, offset + 20))
    return "\(offset) in \(text.debugDescription)"
  }
}
