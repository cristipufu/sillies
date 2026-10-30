import Foundation
import SilliesCore

package typealias SpeakerActivityBatch = SilliesCore.SpeakerActivityBatch

package protocol SpeakerDiarizationEngine: Sendable {
  func append(_ samples: [Float]) async throws -> [SpeakerActivityBatch]
  func finish() async throws -> [SpeakerActivityBatch]
}

package struct SpeakerDiarizationRequest: Sendable {
  package let output: @Sendable (SpeakerActivityBatch) -> Void
  package let failure: LocalSpeechFactory.Failure
  package init(
    output: @escaping @Sendable (SpeakerActivityBatch) -> Void,
    failure: @escaping LocalSpeechFactory.Failure
  ) {
    self.output = output
    self.failure = failure
  }
}

package protocol PreparedDiarizationModel: Sendable {
  func makeChannel(_ request: SpeakerDiarizationRequest) async throws -> any LocalSpeechChannel
  func validate() async throws
}

extension PreparedDiarizationModel {
  package func validate() async throws {
    throw SpeechError.unavailable("This speaker provider does not support model update validation.")
  }
}

package protocol DiarizationProvider: Sendable {
  var id: String { get }
  func prepare(_ request: SpeechPreparation) async throws -> any PreparedDiarizationModel
}

package enum SpeakerDiarizationFactory {
  package typealias Make =
    @Sendable (SpeakerDiarizationRequest) async throws -> any LocalSpeechChannel
}
