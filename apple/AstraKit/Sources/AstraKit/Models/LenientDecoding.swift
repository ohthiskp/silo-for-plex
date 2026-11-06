import Foundation

/// Plex is loose about JSON types: the same field can arrive as a number on one
/// server version and as a string on another (`ratingKey`, `librarySectionID`,
/// `videoResolution`, flags as 0/1). These helpers accept either, so one odd
/// field never drops a whole hub.
extension KeyedDecodingContainer {
  func decodeLenientInt(_ key: Key) throws -> Int? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    if let value = try? decode(Int.self, forKey: key) { return value }
    if let value = try? decode(Double.self, forKey: key) { return Int(value) }
    if let value = try? decode(String.self, forKey: key) { return Int(value) ?? Double(value).map { Int($0) } }
    if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
    return nil
  }

  func decodeLenientDouble(_ key: Key) throws -> Double? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    if let value = try? decode(Double.self, forKey: key) { return value }
    if let value = try? decode(String.self, forKey: key) { return Double(value) }
    return nil
  }

  func decodeLenientString(_ key: Key) throws -> String? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    if let value = try? decode(String.self, forKey: key) { return value }
    if let value = try? decode(Int.self, forKey: key) { return String(value) }
    if let value = try? decode(Double.self, forKey: key) { return String(value) }
    return nil
  }

  func decodeLenientBool(_ key: Key) throws -> Bool? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    if let value = try? decode(Bool.self, forKey: key) { return value }
    if let value = try? decode(Int.self, forKey: key) { return value != 0 }
    if let value = try? decode(String.self, forKey: key) { return value == "1" || value.lowercased() == "true" }
    return nil
  }
}
