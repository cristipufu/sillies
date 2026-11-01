import Foundation
import SilliesCore
import SilliesInference

package enum TextInferenceEvent: Codable, Sendable {
  case delta(String)
  case finished(TextInferenceResponse)
}
package struct TextInferenceAcknowledgement: Codable, Sendable {
  package init() {}
}

package struct TextInferenceRequest: Codable, Sendable {
  package let configuration: TextModelPreparation
  package let generation: TextGenerationRequest
  package init(configuration: TextModelPreparation, generation: TextGenerationRequest) {
    self.configuration = configuration
    self.generation = generation
  }
}

package struct TextInferenceResponse: Codable, Sendable {
  package enum FailureCode: String, Codable, Sendable { case contextLimit }
  package let failureCode: FailureCode?
  package let inputTokens: Int?
  package let text: String?
  package let failure: String?
  package let calls: [ConversationToolCall]?
  package init(output: TextGenerationOutput) {
    inputTokens = output.inputTokens
    failureCode = nil
    text = output.text
    failure = nil
    calls = output.calls
  }
  package init(failure: String, code: FailureCode? = nil) {
    inputTokens = nil
    failureCode = code
    text = nil
    self.failure = failure
    calls = nil
  }
}

/// Keeps the text boundary's recoverable errors while sharing bounded worker framing.
package enum TextInferenceWire {
  package static let maximumMessageBytes = InferenceWire.maximumMessageBytes
  package static func write<T: Encodable>(_ value: T, to handle: FileHandle, deadline: TimeInterval)
    throws
  {
    do { try InferenceWire.write(value, to: handle, deadline: deadline) } catch {
      throw TextModelError.unavailable(error.localizedDescription)
    }
  }
  package static func read<T: Decodable>(
    _ type: T.Type, from handle: FileHandle, deadline: TimeInterval
  ) throws -> T {
    do { return try InferenceWire.read(type, from: handle, deadline: deadline) } catch {
      throw TextModelError.unavailable(error.localizedDescription)
    }
  }
}
