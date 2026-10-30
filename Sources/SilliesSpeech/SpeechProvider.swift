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
