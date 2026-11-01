import Foundation
import FoundationModels
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

@Test func appleToolConversationsUseDeterministicSampling() {
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "A friendly companion", messages: [.init(role: .user, content: "Hello")],
      tools: [.init(name: "search", description: "Search saved material", parameters: [])]),
    maximumTokens: 240, style: .conversation)
  let options = AppleGenerationOptions.make(request)
  #expect(options.samplingMode == .greedy)
  #expect(options.temperature == nil)
  #expect(options.maximumResponseTokens == request.maximumTokens)
}

@Test func appleInternalGenerationErrorExplainsRecoveryWithoutExposingDiagnostics() {
  let underlying = NSError(
    domain: "com.apple.tokengeneration", code: 10,
    userInfo: [NSLocalizedDescriptionKey: "private model input"])
  let error = NSError(
    domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1,
    userInfo: [NSMultipleUnderlyingErrorsKey: [underlying]])
  let failure = AppleGenerationFailure.recoverable(error)
  #expect(failure is TextModelError)
  #expect(failure.localizedDescription.contains("Settings"))
  #expect(!failure.localizedDescription.contains("error -1"))
  let diagnostic = AppleGenerationFailure.diagnostic(error)
  #expect(
    diagnostic
      == "FoundationModels.LanguageModelSession.GenerationError(-1) → com.apple.tokengeneration(10)"
  )
  #expect(!diagnostic.contains("private model input"))
}

@Test func appleFailureTranslationPreservesCancellationContextAndDocumentedErrors() {
  #expect(AppleGenerationFailure.recoverable(CancellationError()) is CancellationError)
  let context = LanguageModelSession.GenerationError.Context(debugDescription: "fixture")
  let overflow = AppleGenerationFailure.recoverable(
    LanguageModelSession.GenerationError.exceededContextWindowSize(context))
  guard case TextModelError.contextLimit = overflow else {
    Issue.record("Context exhaustion must reach the compaction recovery path")
    return
  }
  let refusal = LanguageModelSession.GenerationError.guardrailViolation(context)
  #expect(AppleGenerationFailure.recoverable(refusal) is LanguageModelSession.GenerationError)
  let io = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
  #expect((AppleGenerationFailure.recoverable(io) as NSError) == io)
}

@Test func appleFailureDiagnosticsBoundUnderlyingErrorTrees() {
  var error = NSError(domain: "leaf", code: 1)
  for _ in 0..<20 {
    error = NSError(
      domain: "engine", code: 2,
      userInfo: [NSMultipleUnderlyingErrorsKey: Array(repeating: error, count: 8)])
  }
  let diagnostic = AppleGenerationFailure.diagnostic(error)
  #expect(!diagnostic.contains("leaf"))
  #expect(diagnostic.count < 2_000)
}
