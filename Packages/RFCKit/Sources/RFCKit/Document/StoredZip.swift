import Foundation

/// A zip archive whose every entry is stored, not compressed: what an EPUB needs,
/// and all it needs (#408). A reader of EPUB must read stored entries, and the
/// `mimetype` entry must be one, so the writer needs CRC-32 and no compression.
///
/// Every entry is dated 1 January 1980, the format's first day, so the same
/// entries make the same bytes.
enum StoredZip {
  struct Entry {
    var path: String
    var data: Data
  }

  static func archive(_ entries: [Entry]) -> Data {
    var archive = Data()
    var directory = Data()
    for entry in entries {
      let name = Data(entry.path.utf8)
      let checksum = crc32(entry.data)
      let size = UInt32(entry.data.count)
      let offset = UInt32(archive.count)
      // Bit 11: the name is UTF-8.
      let flags: UInt16 = entry.path.allSatisfy(\.isASCII) ? 0 : 1 << 11

      archive.append(littleEndian: UInt32(0x0403_4b50))
      archive.append(littleEndian: versionNeeded)
      archive.append(littleEndian: flags)
      archive.append(littleEndian: UInt16(0))  // stored
      archive.append(littleEndian: dosTime)
      archive.append(littleEndian: dosDate)
      archive.append(littleEndian: checksum)
      archive.append(littleEndian: size)
      archive.append(littleEndian: size)
      archive.append(littleEndian: UInt16(name.count))
      archive.append(littleEndian: UInt16(0))  // no extra field
      archive.append(name)
      archive.append(entry.data)

      directory.append(littleEndian: UInt32(0x0201_4b50))
      directory.append(littleEndian: versionNeeded)  // made by
      directory.append(littleEndian: versionNeeded)
      directory.append(littleEndian: flags)
      directory.append(littleEndian: UInt16(0))
      directory.append(littleEndian: dosTime)
      directory.append(littleEndian: dosDate)
      directory.append(littleEndian: checksum)
      directory.append(littleEndian: size)
      directory.append(littleEndian: size)
      directory.append(littleEndian: UInt16(name.count))
      directory.append(littleEndian: UInt16(0))  // extra field
      directory.append(littleEndian: UInt16(0))  // comment
      directory.append(littleEndian: UInt16(0))  // disk
      directory.append(littleEndian: UInt16(0))  // internal attributes
      directory.append(littleEndian: UInt32(0))  // external attributes
      directory.append(littleEndian: offset)
      directory.append(name)
    }
    let directoryOffset = UInt32(archive.count)
    archive.append(directory)
    archive.append(littleEndian: UInt32(0x0605_4b50))
    archive.append(littleEndian: UInt16(0))  // this disk
    archive.append(littleEndian: UInt16(0))  // the directory's disk
    archive.append(littleEndian: UInt16(entries.count))
    archive.append(littleEndian: UInt16(entries.count))
    archive.append(littleEndian: UInt32(directory.count))
    archive.append(littleEndian: directoryOffset)
    archive.append(littleEndian: UInt16(0))  // comment
    return archive
  }

  /// 1.0: stored entries, no more.
  private static let versionNeeded: UInt16 = 10
  /// Midnight.
  private static let dosTime: UInt16 = 0
  /// 1 January 1980: years since 1980 in bits 9–15, the month in 5–8, the day in 0–4.
  private static let dosDate: UInt16 = (1 << 5) | 1

  /// The CRC-32 zip uses (ISO 3309, reflected, polynomial 0xEDB88320).
  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static let crcTable: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }
}

extension Data {
  fileprivate mutating func append<Value: FixedWidthInteger>(littleEndian value: Value) {
    for shift in stride(from: 0, to: Value.bitWidth, by: 8) {
      append(UInt8(truncatingIfNeeded: value >> shift))
    }
  }
}
