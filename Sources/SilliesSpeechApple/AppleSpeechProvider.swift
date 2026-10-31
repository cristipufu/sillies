import SilliesSpeech

package struct AppleSpeechProvider: SpeechProvider, PreparedSpeechModel {
  package let id = "apple"
  package init() {}

  package func languages(_ request: SpeechLanguageRequest) async throws -> SpeechLanguageCatalog {
    try Task.checkCancellation()
    let discovered = await AppleSpeechLanguageDiscovery.load()
    try Task.checkCancellation()
    return SpeechLanguageCatalog(languages: discovered.languages, model: request.model)
  }

  package func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    try Task.checkCancellation()
    return self
  }

  package func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel {
    guard request.language.isInstalled else {
      throw SpeechError.unavailable(
        "Install the Apple speech model for \(request.language.name) first.")
    }
    return try await AnalyzerSpeechChannel.make(
      locale: request.language.locale, output: request.output, failure: request.failure,
      context: request.context)
  }

  package static func makeChannel(
    language: SpeechLanguage, output: @escaping LocalSpeechFactory.Output,
    failure: @escaping LocalSpeechFactory.Failure
  ) async throws -> any LocalSpeechChannel {
    guard language.isInstalled else {
      throw SpeechError.unavailable(
        "The Apple speech model for \(language.name) is not installed. Choose a language marked Ready on this Mac."
      )
    }
    return try await AnalyzerSpeechChannel.make(
      locale: language.locale, output: output, failure: failure)
  }
}
