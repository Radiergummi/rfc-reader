import Foundation
import RFCKit

extension DocumentTextBuilder {
  /// An index as the blocks prep's markup read as before the index was a block of
  /// its own: a line of letters linking to the groups, then each group's letter and
  /// a list of its terms with their locators (`IndexBlock.definitionList`). The reader sets an
  /// index as one later (the design's part 3); until then it reads as it did, except
  /// that the letters now lead to their groups, whose anchors prep set on empty
  /// paragraphs the parser dropped.
  static func plainBlocks(of index: IndexBlock) -> [Block] {
    let letters = index.groups.map { group -> [Inline] in
      [.crossReference(CrossReference(target: .anchor(group.anchor), text: group.label))]
    }
    var blocks: [Block] = [
      .paragraph(
        Paragraph(Array(letters.joined(separator: [.text(" ")])), anchor: IndexBlock.anchor))
    ]
    for group in index.groups {
      blocks.append(.paragraph(Paragraph([.text(group.label)], anchor: group.anchor)))
      blocks.append(.definitionList(IndexBlock.definitionList(group.entries)))
    }
    return blocks
  }
}
