import CoreML
import SilliesSpeech
import Testing

@testable import SilliesSpeechActivity

@Test func incompatibleNativeActivityTensorsFailBeforePrediction() throws {
  typealias Tensor = SpeechActivityModelInterface.Tensor
  let inputs: [String: Tensor] = [
    "audio_input": .init(shape: [1, 4160], dataType: .float32),
    "hidden_state": .init(shape: [1, 128], dataType: .float32),
    "cell_state": .init(shape: [1, 128], dataType: .float32),
  ]
  let outputs: [String: Tensor] = [
    "vad_output": .init(shape: [1, 1, 1], dataType: .float32),
    "new_hidden_state": .init(shape: [1, 128], dataType: .float32),
    "new_cell_state": .init(shape: [1, 128], dataType: .float32),
  ]
  try SpeechActivityModelInterface.validate(inputs: inputs, outputs: outputs)
  for key in outputs.keys {
    var damaged = outputs
    damaged.removeValue(forKey: key)
    #expect(throws: SpeechError.self) {
      try SpeechActivityModelInterface.validate(inputs: inputs, outputs: damaged)
    }
    for tensor in [
      Tensor(shape: [1], dataType: .float32), Tensor(shape: [1, 128], dataType: .float16),
    ] {
      damaged[key] = tensor
      #expect(throws: SpeechError.self) {
        try SpeechActivityModelInterface.validate(inputs: inputs, outputs: damaged)
      }
    }
  }
  var damaged = inputs
  damaged["audio_input"] = .init(shape: [1, 0], dataType: .float32)
  #expect(throws: SpeechError.self) {
    try SpeechActivityModelInterface.validate(inputs: damaged, outputs: outputs)
  }
}

@Test func fixedEnumeratedCoreMLShapesAreAcceptedWhileVariableNativeBuffersAreRejected() {
  #expect(
    SpeechActivityModelInterface.hasFixedShape(
      kind: .enumerated, shape: [1, 128], alternatives: [[1, 128]]))
  #expect(
    SpeechActivityModelInterface.hasFixedShape(
      kind: .unspecified, shape: [1, 128], alternatives: []))
  #expect(
    !SpeechActivityModelInterface.hasFixedShape(
      kind: .enumerated, shape: [1, 128], alternatives: [[1, 128], [1, 1]]))
  #expect(
    !SpeechActivityModelInterface.hasFixedShape(kind: .range, shape: [1, 128], alternatives: []))
}
