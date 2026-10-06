extension RandomAccessCollection {
  /// The first index whose element belongs in the second partition, or `endIndex`
  /// when none does. The collection must already be partitioned by it: every
  /// element for which it is false comes before every one for which it is true.
  /// A binary search, as `swift-algorithms` spells it.
  func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Index {
    var low = startIndex
    var count = self.count
    while count > 0 {
      let half = count / 2
      let middle = index(low, offsetBy: half)
      if belongsInSecondPartition(self[middle]) {
        count = half
      } else {
        low = index(after: middle)
        count -= half + 1
      }
    }
    return low
  }
}
