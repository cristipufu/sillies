import Foundation

/// Only bundled, contributor-authored display copy belongs here; never user content or model prompts.
enum LocalizedCatalogText {
  static func value(_ source: String) -> String {
    String(localized: String.LocalizationValue(source))
  }
}
