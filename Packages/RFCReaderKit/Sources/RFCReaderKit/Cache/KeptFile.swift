import Foundation

/// A JSON file the store keeps beside the index: written whole, and read back with
/// when it was written, which for a file fetched is when it was fetched (#758).
struct KeptFile<Value> {
  let url: URL
  let decode: (Data) throws -> Value

  /// The value kept and when it was written. Nil when there is none, or it no longer
  /// decodes: a newer version, after a downgrade.
  func read() -> (value: Value, keptAt: Date)? {
    guard let data = try? Data(contentsOf: url), let value = try? decode(data) else {
      return nil
    }
    return (value, DocumentStore.modificationDate(of: url) ?? .distantPast)
  }

  func write(_ data: Data) throws {
    try data.write(to: url, options: .atomic)
  }
}
