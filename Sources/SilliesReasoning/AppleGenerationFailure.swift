import Foundation
import FoundationModels
import SilliesTextModels

/// Keep native control-flow errors intact and translate undocumented engine errors at the boundary.
enum AppleGenerationFailure {
  private static let maximumDiagnosticDepth = 4
  private static let maximumUnderlyingErrors = 3
  private static let maximumDomainCharacters = 160

  static func recoverable(_ error: any Error) -> any Error {
    if error is CancellationError { return error }
    if let tool = error as? LanguageModelSession.ToolCallError {
      return recoverable(tool.underlyingError)
    }
    if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
      return TextModelError.contextLimit
    }
    if #available(macOS 27.0, *), case LanguageModelError.contextSizeExceeded = error {
      return TextModelError.contextLimit
    }
    // Documented errors already explain refusals, unavailable assets and unsupported languages.
    if error is LanguageModelSession.GenerationError { return error }
    if #available(macOS 27.0, *), error is LanguageModelError { return error }
    let native = error as NSError
    guard native.domain.hasPrefix("FoundationModels.") else { return error }
    // Never log descriptions, prompts, tool arguments or arbitrary userInfo from the model.
    fputs("Apple text generation failed: \(diagnostic(native))\n", stderr)
    return TextModelError.unavailable(
      String(
        localized:
          "Apple’s on-device AI couldn’t generate a response. Try again, or choose a downloaded text model in Settings → Local AI."
      ))
  }

  static func diagnostic(_ error: NSError, depth: Int = 0) -> String {
    let identifier = "\(error.domain.prefix(maximumDomainCharacters))(\(error.code))"
    guard depth < maximumDiagnosticDepth else { return identifier }
    let underlying =
      (error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError])
      ?? (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { [$0] } ?? []
    let causes = underlying.prefix(maximumUnderlyingErrors).map {
      diagnostic($0, depth: depth + 1)
    }
    return ([identifier] + causes).joined(separator: " → ")
  }
}
