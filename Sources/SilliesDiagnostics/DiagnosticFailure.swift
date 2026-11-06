import Foundation

/// Native descriptions and userInfo often contain content or paths. Preserve identity only.
package struct DiagnosticFailure: Codable, Sendable, Equatable {
  private static let knownDomains: Set<String> = [
    NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain, NSOSStatusErrorDomain,
    "Swift.CancellationError", "FoundationModels.LanguageModelSession.GenerationError",
    "kAFAssistantErrorDomain", "SFSpeechErrorDomain", "com.apple.coreaudio.avfaudio",
  ]
  package let type: String
  package let domain: String
  package let code: Int

  package init(_ error: any Error) {
    let native = error as NSError
    type = DiagnosticEvent.identifier(String(reflecting: Swift.type(of: error))) ?? "other"
    domain = Self.knownDomains.contains(native.domain) ? native.domain : "other"
    code = native.code
  }

  private init(type: String, domain: String, code: Int) {
    self.type = type
    self.domain = domain
    self.code = code
  }

  func validated() -> Self {
    .init(
      type: DiagnosticEvent.identifier(type) ?? "other",
      domain: Self.knownDomains.contains(domain) ? domain : "other", code: code)
  }
}
