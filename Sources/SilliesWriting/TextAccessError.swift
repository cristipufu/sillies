import Foundation

package enum TextAccessError: LocalizedError {
  case permission, unsupported, protectedField, changed, failed, clipboardRestore
  package var errorDescription: String? {
    switch self {
    case .permission: "Enable Accessibility to insert text. Your result can still be copied."
    case .unsupported: "This field does not support safe insertion. Copy the result instead."
    case .protectedField: "Dictation is unavailable in a protected field."
    case .changed: "The destination changed. Your text is ready to copy or paste."
    case .failed: "Insertion could not be confirmed. Check the field before pasting again."
    case .clipboardRestore:
      "Text may already be inserted, but the previous clipboard could not be restored. Check the field before pasting again."
    }
  }
}
