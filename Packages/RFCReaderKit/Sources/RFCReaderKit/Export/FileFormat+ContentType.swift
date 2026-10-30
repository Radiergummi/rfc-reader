import RFCKit
import UniformTypeIdentifiers

extension FileFormat {
  /// The type of the file the RFC Editor publishes in this format: what iOS's Save
  /// to Files saves a downloaded format row as (#577), and so what keeps its extension.
  public var contentType: UTType {
    UTType(filenameExtension: pathExtension) ?? .data
  }
}
