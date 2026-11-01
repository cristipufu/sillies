import Foundation

package enum TextAccessError: LocalizedError {
  case permission, unsupported, protectedField, changed, failed, clipboardRestore
  package var errorDescription: String? {
    switch self {
    case .permission:
      String(localized: "Enable Accessibility to insert text. Your result can still be copied.")
    case .unsupported:
      String(localized: "This field does not support safe insertion. Copy the result instead.")
    case .protectedField: String(localized: "Dictation is unavailable in a protected field.")
    case .changed:
      String(localized: "The destination changed. Your text is ready to copy or paste.")
    case .failed:
      String(localized: "Insertion could not be confirmed. Check the field before pasting again.")
    case .clipboardRestore:
      String(
        localized:
          "Text may already be inserted, but the previous clipboard could not be restored. Check the field before pasting again."
      )
    }
  }
}
