import Foundation

/// The name a file saved to Downloads is given: its own, or with a number before
/// its extension when that is taken, as Safari names a second download of the same
/// file ("rfc9110 2.pdf").
///
/// Asked name by name rather than handed a listing, so a Downloads folder of
/// thousands of files is never listed to save one.
public enum DownloadName {
  public static func unique(_ name: String, isTaken: (String) -> Bool) -> String {
    guard isTaken(name) else { return name }
    let file = name as NSString
    let stem = file.deletingPathExtension
    let suffix = file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)"
    var number = 2
    while isTaken("\(stem) \(number)\(suffix)") {
      number += 1
    }
    return "\(stem) \(number)\(suffix)"
  }
}
