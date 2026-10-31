import Foundation
import SilliesInference

package struct TextInferenceRequest: Codable, Sendable {
  package let configuration: TextModelPreparation
  package let generation: TextGenerationRequest
  package init(configuration: TextModelPreparation, generation: TextGenerationRequest) {
    self.configuration = configuration
    self.generation = generation
  }
}

package struct TextInferenceResponse: Codable, Sendable {
  package let text: String?
  package let failure: String?
  package init(text: String? = nil, failure: String? = nil) {
    self.text = text
    self.failure = failure
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
