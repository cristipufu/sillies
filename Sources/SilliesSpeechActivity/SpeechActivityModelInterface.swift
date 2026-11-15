import CoreML
import FluidAudio
import Foundation
import SilliesSpeech

/// Fixed tensor contracts prevent the SDK's native buffer reads from accepting incompatible models.
enum SpeechActivityModelInterface {
  struct Tensor: Equatable {
    let shape: [Int]
    let dataType: MLMultiArrayDataType
  }
  private static let recurrentFeatures = 128
  private static let inputs: [String: Tensor] = [
    "audio_input": .init(
      shape: [1, VadManager.chunkSize + VadState.contextLength], dataType: .float32),
    "hidden_state": .init(shape: [1, recurrentFeatures], dataType: .float32),
    "cell_state": .init(shape: [1, recurrentFeatures], dataType: .float32),
  ]
  private static let outputs: [String: Tensor] = [
    "vad_output": .init(shape: [1, 1, 1], dataType: .float32),
    "new_hidden_state": .init(shape: [1, recurrentFeatures], dataType: .float32),
    "new_cell_state": .init(shape: [1, recurrentFeatures], dataType: .float32),
  ]

  static func validate(_ description: MLModelDescription) throws {
    try validate(
      inputs: tensors(description.inputDescriptionsByName),
      outputs: tensors(description.outputDescriptionsByName))
  }

  static func validate(
    inputs actualInputs: [String: Tensor], outputs actualOutputs: [String: Tensor]
  )
    throws
  {
    guard actualInputs == inputs, actualOutputs == outputs else {
      throw SpeechError.invalidAudioFormat
    }
  }

  private static func tensors(_ descriptions: [String: MLFeatureDescription]) throws -> [String:
    Tensor]
  {
    try descriptions.mapValues { feature in
      guard feature.type == .multiArray, let array = feature.multiArrayConstraint,
        hasFixedShape(
          kind: array.shapeConstraint.type, shape: array.shape,
          alternatives: array.shapeConstraint.enumeratedShapes), array.shape.count <= 3
      else { throw SpeechError.invalidAudioFormat }
      let shape = array.shape.compactMap { Int(exactly: $0.doubleValue) }
      guard shape.count == array.shape.count else { throw SpeechError.invalidAudioFormat }
      return Tensor(shape: shape, dataType: array.dataType)
    }
  }

  static func hasFixedShape(
    kind: MLMultiArrayShapeConstraintType, shape: [NSNumber], alternatives: [[NSNumber]]
  ) -> Bool {
    switch kind {
    case .unspecified: return true
    case .enumerated:
      return !alternatives.isEmpty && alternatives.allSatisfy { $0 == shape }
    default: return false
    }
  }

}
