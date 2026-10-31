import Foundation

/// Cleanup may remove fillers, but cannot drop numeric or code tokens.
public enum TextCleanupGuard {
  private static let maximumExpansion = 2
  private static let formattingAllowance = 80
  public enum Operation { case editing, rewriting, translation }
  public static func accepts(
    _ output: String, source: String, vocabulary: [String], operation: Operation = .editing
  ) -> Bool {
    guard !output.isEmpty, output.count <= source.count * maximumExpansion + formattingAllowance
    else { return false }
    let tokens = source.split { $0.isWhitespace || ",;!?()\"".contains($0) }
    let protected = tokens.filter {
      $0.contains(where: \.isNumber) || $0.contains("_") || $0.contains("/")
        || $0.contains("@") || $0.contains("=")
    }
    let names = source.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.filter {
      $0.count > 1 && $0.first?.isUppercase == true && !["um", "uh"].contains($0.lowercased())
    }
    return protected.allSatisfy { output.contains($0) }
      && (operation != .editing
        || names.allSatisfy { output.localizedCaseInsensitiveContains($0) })
      && vocabulary.filter { source.localizedCaseInsensitiveContains($0) }
        .allSatisfy { output.localizedCaseInsensitiveContains($0) }
  }
}
