import Foundation

/// Which characters of a build's storage are which characters of the document's model
/// text (`ModelText`), recorded by `DocumentTextBuilder` as it appends (#522).
///
/// A storage character either maps to a model character or is the storage's own: a
/// section number, a list marker, a chip's attachment character, a stacked table's
/// label. A model character either maps to a storage character or is hidden in this
/// build: a join between two blocks that the storage set as something else, a stacked
/// table's header row, the RFC 8792 header a block shown unfolded has lost. The two
/// directions are pure queries, and neither assumes the storage is in the model's
/// order: a figure's caption comes after its artwork, and a grid row sets each cell's
/// lines side by side.
public struct PositionMap: Sendable {
  /// A run of storage characters that are, in order, a run of model characters.
  public struct Run: Sendable, Hashable {
    /// UTF-16 offsets into the storage and the model text.
    public let storage: Int
    public let model: Int
    public let length: Int

    var storageEnd: Int { storage + length }
    var modelEnd: Int { model + length }
  }

  /// The document's model text.
  public let model: ModelText
  /// By where they start in the storage; no two share a storage or a model character.
  public let runs: [Run]
  /// The runs again, by where they start in the model text.
  private let byModel: [Run]
  /// The model text this build declares it does not show, sorted and apart.
  public let hidden: [Range<Int>]

  init(model: ModelText, runs: [Run], hidden: [Range<Int>]) {
    self.model = model
    self.runs = runs.sorted { $0.storage < $1.storage }
    byModel = runs.sorted { $0.model < $1.model }
    self.hidden = hidden.sorted { $0.lowerBound < $1.lowerBound }
  }

  /// The model text a storage range covers: from the first model character any of its
  /// storage characters maps to, to the last. A selection that starts on a section
  /// number therefore starts at the heading's first word, and one that ends on a list
  /// marker ends at the item before it. Nil when nothing in the range maps.
  public func modelRange(forStorage range: NSRange) -> Range<Int>? {
    let end = NSMaxRange(range)
    var first = runs.partitioningIndex { $0.storageEnd > range.location }
    var lower = Int.max
    var upper = Int.min
    while first < runs.count, runs[first].storage < end {
      let run = runs[first]
      let start = max(run.storage, range.location)
      let stop = min(run.storageEnd, end)
      if start < stop {
        lower = min(lower, run.model + start - run.storage)
        upper = max(upper, run.model + stop - run.storage)
      }
      first += 1
    }
    return lower < upper ? lower..<upper : nil
  }

  /// The model offset the storage character at `offset` maps to, or nil when it is the
  /// storage's own.
  public func modelOffset(forStorage offset: Int) -> Int? {
    let index = runs.partitioningIndex { $0.storageEnd > offset }
    guard index < runs.count, runs[index].storage <= offset else { return nil }
    return runs[index].model + offset - runs[index].storage
  }

  /// The storage a model range is drawn in: every run of it this build shows, in
  /// storage order, adjacent ones joined. Empty when the build shows none of it.
  public func storageRanges(forModel range: Range<Int>) -> [NSRange] {
    var index = byModel.partitioningIndex { $0.modelEnd > range.lowerBound }
    var pieces: [NSRange] = []
    while index < byModel.count, byModel[index].model < range.upperBound {
      let run = byModel[index]
      let start = max(run.model, range.lowerBound)
      let stop = min(run.modelEnd, range.upperBound)
      if start < stop {
        pieces.append(NSRange(location: run.storage + start - run.model, length: stop - start))
      }
      index += 1
    }
    pieces.sort { $0.location < $1.location }
    var joined: [NSRange] = []
    for piece in pieces {
      if let last = joined.last, NSMaxRange(last) == piece.location {
        joined[joined.count - 1].length += piece.length
      } else {
        joined.append(piece)
      }
    }
    return joined
  }

  /// Where a model range is drawn as one shape each: `storageRanges(forModel:)`, with
  /// two pieces joined where only the storage's own characters lie between them, such
  /// as a chip's symbol, a list marker or a section number. A highlight across a
  /// heading and the paragraph under it is then one fill, as it reads, and one over a
  /// figure's title and its artwork stays two, the caption being far from the start.
  public func drawnRanges(forModel range: Range<Int>) -> [NSRange] {
    var joined: [NSRange] = []
    for piece in storageRanges(forModel: range) {
      if let last = joined.last,
        !mapsAny(in: NSRange(location: NSMaxRange(last), length: piece.location - NSMaxRange(last)))
      {
        joined[joined.count - 1] = NSRange(
          location: last.location, length: NSMaxRange(piece) - last.location)
      } else {
        joined.append(piece)
      }
    }
    return joined
  }

  /// Whether any storage character in `range` maps to a model character.
  private func mapsAny(in range: NSRange) -> Bool {
    guard range.length > 0 else { return false }
    let index = runs.partitioningIndex { $0.storageEnd > range.location }
    return index < runs.count && runs[index].storage < NSMaxRange(range)
  }

  /// The storage offset the model character at `offset` is drawn at, or nil when this
  /// build does not show it.
  public func storageOffset(forModel offset: Int) -> Int? {
    let index = byModel.partitioningIndex { $0.modelEnd > offset }
    guard index < byModel.count, byModel[index].model <= offset else { return nil }
    return byModel[index].storage + offset - byModel[index].model
  }
}

extension PositionMap {
  /// Records a map as a build appends. Runs that continue each other in both texts are
  /// joined as they come.
  struct Recorder {
    let model: ModelText
    /// Where the next model character the build will reach is.
    var cursor = 0
    private(set) var runs: [Run] = []
    /// How many runs are recorded, for `hideUnmapped(in:since:)`.
    var runCount: Int { runs.count }
    private(set) var hidden: [Range<Int>] = []
    /// One past the last storage character mapped, so a join knows whether the
    /// newline before it is taken.
    private(set) var mappedStorageEnd = 0

    init(model: ModelText) {
      self.model = model
    }

    var map: PositionMap {
      PositionMap(model: model, runs: runs, hidden: hidden)
    }

    mutating func map(storage: Int, model modelOffset: Int, length: Int) {
      guard length > 0 else { return }
      if let last = runs.last, last.storageEnd == storage, last.modelEnd == modelOffset {
        runs[runs.count - 1] = Run(
          storage: last.storage, model: last.model, length: last.length + length)
      } else {
        runs.append(Run(storage: storage, model: modelOffset, length: length))
      }
      mappedStorageEnd = max(mappedStorageEnd, storage + length)
    }

    mutating func hide(_ range: Range<Int>) {
      guard !range.isEmpty else { return }
      if let last = hidden.last, last.upperBound == range.lowerBound {
        hidden[hidden.count - 1] = last.lowerBound..<range.upperBound
      } else {
        hidden.append(range)
      }
    }

    /// Hides whatever in `range` of the model text no run maps, of those recorded from
    /// `firstRun` on: for an element whose storage is not in the model's order, such as
    /// a table, which records its runs where they fall and declares the rest after.
    mutating func hideUnmapped(in range: Range<Int>, since firstRun: Int) {
      // The run before may have been extended into the range by its first character.
      let covered = runs[max(0, firstRun - 1)...]
        .map { $0.model..<$0.modelEnd }
        .filter { $0.overlaps(range) }
        .sorted { $0.lowerBound < $1.lowerBound }
      var position = range.lowerBound
      for run in covered {
        if run.lowerBound > position { hide(position..<run.lowerBound) }
        position = max(position, run.upperBound)
      }
      if position < range.upperBound { hide(position..<range.upperBound) }
    }

    /// The model characters at the cursor that this build does not show.
    mutating func skip(_ length: Int) {
      hide(cursor..<cursor + length)
      cursor += length
    }

    /// Aligns the storage characters in `range` with the model text from `modelStart`:
    /// a character that matches the next model character maps to it, and one that does
    /// not, such as a chip's attachment character or its word joiner, is the storage's
    /// own. Returns how many model characters it consumed. Anything the storage left out
    /// is left unmapped, and the guard reports it (`PositionMapTests`).
    @discardableResult
    mutating func align(_ storage: NSString, range: NSRange, model modelStart: Int) -> Int {
      var modelIndex = modelStart
      var index = range.location
      let end = NSMaxRange(range)
      let units = model.units
      while index < end {
        if modelIndex < units.count, units[modelIndex] == storage.character(at: index) {
          var length = 1
          while index + length < end, modelIndex + length < units.count,
            storage.character(at: index + length) == units[modelIndex + length]
          {
            length += 1
          }
          map(storage: index, model: modelIndex, length: length)
          index += length
          modelIndex += length
        } else {
          index += 1
        }
      }
      return modelIndex - modelStart
    }

    /// `align(_:range:model:)` from the cursor, moving it on.
    mutating func advance(_ storage: NSString, range: NSRange) {
      cursor += align(storage, range: range, model: cursor)
    }

    /// The join at the cursor, a newline or a tab between two elements: mapped to the
    /// storage's last character when that is the same character and nothing took it,
    /// hidden otherwise.
    mutating func join(storage: NSString) {
      guard cursor < model.units.count else { return }
      let last = storage.length - 1
      if last >= 0, last >= mappedStorageEnd, storage.character(at: last) == model.units[cursor] {
        map(storage: last, model: cursor, length: 1)
      } else {
        hide(cursor..<cursor + 1)
      }
      cursor += 1
    }
  }
}

extension PositionMap {
  /// Which characters of `shown` are which of `model`, as runs, for text the reader
  /// shows other than as written: a verbatim block with its tabs expanded, its shared
  /// indent taken off, or its RFC 8792 folds undone. Each of those changes a line in
  /// place, so lines are aligned with lines when there are as many of each, and the
  /// whole text otherwise, by the shortest edit between the two. A character that only
  /// one of them has is its own: a tab's spaces in `shown`, the header and the
  /// backslashes of a fold in `model`.
  static func alignment(of shown: [UInt16], to model: [UInt16]) -> [Run] {
    guard shown != model else { return shown.isEmpty ? [] : [Run(storage: 0, model: 0, length: shown.count)] }
    let shownLines = lineRanges(of: shown)
    let modelLines = lineRanges(of: model)
    guard shownLines.count == modelLines.count else {
      return differenceRuns(shown[...], model[...], shownStart: 0, modelStart: 0)
    }
    var runs: [Run] = []
    for (shownLine, modelLine) in zip(shownLines, modelLines) {
      // The newline that ends a line, where it has one, is part of the line here.
      let line = differenceRuns(
        shown[shownLine], model[modelLine], shownStart: shownLine.lowerBound,
        modelStart: modelLine.lowerBound)
      for run in line {
        if let last = runs.last, last.storageEnd == run.storage, last.modelEnd == run.model {
          runs[runs.count - 1] = Run(
            storage: last.storage, model: last.model, length: last.length + run.length)
        } else {
          runs.append(run)
        }
      }
    }
    return runs
  }

  /// Each line's range, its newline included.
  private static func lineRanges(of units: [UInt16]) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    var start = 0
    for (index, unit) in units.enumerated() where unit == 0x0A {
      ranges.append(start..<index + 1)
      start = index + 1
    }
    if start < units.count || units.isEmpty { ranges.append(start..<units.count) }
    return ranges
  }

  private static func differenceRuns(
    _ shown: ArraySlice<UInt16>, _ model: ArraySlice<UInt16>, shownStart: Int, modelStart: Int
  ) -> [Run] {
    if shown.elementsEqual(model) {
      return shown.isEmpty ? [] : [Run(storage: shownStart, model: modelStart, length: shown.count)]
    }
    let shownArray = Array(shown)
    let modelArray = Array(model)
    let difference = shownArray.difference(from: modelArray)
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    var runs: [Run] = []
    var modelIndex = 0
    var shownIndex = 0
    while modelIndex < modelArray.count || shownIndex < shownArray.count {
      if removed.contains(modelIndex) {
        modelIndex += 1
      } else if inserted.contains(shownIndex) {
        shownIndex += 1
      } else {
        let storage = shownStart + shownIndex
        let model = modelStart + modelIndex
        if let last = runs.last, last.storageEnd == storage, last.modelEnd == model {
          runs[runs.count - 1] = Run(
            storage: last.storage, model: last.model, length: last.length + 1)
        } else {
          runs.append(Run(storage: storage, model: model, length: 1))
        }
        modelIndex += 1
        shownIndex += 1
      }
    }
    return runs
  }
}
