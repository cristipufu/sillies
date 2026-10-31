import Foundation
import SilliesCore

package struct SpeechPreparation: Sendable {
  package let model: SpeechModelDescriptor
  package let directory: URL?
  package init(model: SpeechModelDescriptor, directory: URL?) {
    self.model = model
    self.directory = directory
  }
}

package struct SpeechChannelRequest: Sendable {
  package let language: SpeechLanguage
  package let output: LocalSpeechFactory.Output
  package let failure: LocalSpeechFactory.Failure
  package var context = SpeechRecognitionContext()
  package init(
    language: SpeechLanguage, output: @escaping LocalSpeechFactory.Output,
    failure: @escaping LocalSpeechFactory.Failure
  ) {
    self.language = language
    self.output = output
    self.failure = failure
  }
}

package protocol SpeechProvider: Sendable {
  var id: String { get }
  func languages(_ request: SpeechLanguageRequest) async throws -> SpeechLanguageCatalog
  func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel
}

package protocol PreparedSpeechModel: Sendable {
  func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel
  func validate() async throws
}

extension PreparedSpeechModel {
  package func validate() async throws {
    throw SpeechError.unavailable("This speech provider does not support model update validation.")
  }
}

package struct SpeechLanguageRequest: Sendable {
  package enum Availability: Sendable { case installed, missing }
  package let model: SpeechModelDescriptor
  package let availability: Availability
  package init(model: SpeechModelDescriptor, availability: Availability) {
    self.model = model
    self.availability = availability
  }
}

extension SpeechProvider {
  /// Downloaded providers use catalog capabilities. System providers can discover installed assets.
  package func languages(_ request: SpeechLanguageRequest) async throws -> SpeechLanguageCatalog {
    try Task.checkCancellation()
    let capabilities = request.model.capabilities
    let installed = request.availability == .installed
    var languages: [SpeechLanguage] = []
    if capabilities.supportsAutomaticDetection {
      languages.append(
        .init(
          id: SpeechLanguage.automatic.id, name: SpeechLanguage.automatic.name,
          isInstalled: installed))
    }
    if capabilities.languageControl != .automatic {
      languages += capabilities.languages.map {
        SpeechLanguage(
          id: $0, name: Locale.current.localizedString(forLanguageCode: $0) ?? $0,
          isInstalled: installed)
      }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    return SpeechLanguageCatalog(languages: languages, model: request.model)
  }
}
