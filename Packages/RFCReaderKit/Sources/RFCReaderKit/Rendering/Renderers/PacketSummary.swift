import RFCKit

/// What VoiceOver says for a rendered packet diagram in place of its box drawing:
/// the row's width, then every field and how wide it is.
enum PacketSummary {
  static func spoken(_ diagram: PacketDiagram) -> String {
    let fields = diagram.fields.map { field in
      let width =
        field.isVariableLength
        ? "variable length" : field.bitWidth == 1 ? "1 bit" : "\(field.bitWidth) bits"
      return "\(field.name), \(width)"
    }
    return "Packet diagram, \(diagram.bitsPerRow) bits a row: " + fields.joined(separator: "; ")
  }
}
