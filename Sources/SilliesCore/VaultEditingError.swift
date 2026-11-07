import Foundation

public enum VaultEditingError: Error, LocalizedError {
  case missingRecord, revisionConflict, invalidValue, bookmarkLimit, searchTooShort, searchTooLong
  public var errorDescription: String? {
    switch self {
    case .missingRecord:
      String(localized: "This item is no longer in your Vault. Your draft is still available.")
    case .revisionConflict:
      String(
        localized:
          "This text changed while you were editing. Your draft has been kept so you can compare the versions."
      )
    case .invalidValue: String(localized: "This Vault change contains an unsupported value.")
    case .bookmarkLimit:
      String(localized: "This recording has 200 bookmarks. Remove one before adding another.")
    case .searchTooShort:
      String(
        localized:
          "Exact text search needs at least 3 characters. Use word search for shorter terms.")
    case .searchTooLong: String(localized: "Use up to 512 characters in a Vault search.")
    }
  }
}
