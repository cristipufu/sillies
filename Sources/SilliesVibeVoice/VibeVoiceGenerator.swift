import MLX
import SilliesTTS

/// The publisher's interleaved schedule: five text tokens, then six acoustic frames.
struct VibeVoiceGenerator {
  private static let textWindow = 5
  private static let speechWindow = 6
  private static let maximumSpeechFrames = 450
  private static let connectorEpsilon: Float = 1e-6
  private let embedding: VibeVoiceEmbedding
  private let textType: MLXArray
  private let speechType: MLXArray
  private let textStack: VibeVoiceTransformer
  private let speechStack: VibeVoiceTransformer
  private let diffusion: VibeVoiceDiffusion
  private let connectorInput: VibeVoiceLinear
  private let connectorNorm: MLXArray
  private let connectorOutput: VibeVoiceLinear
  private let endHidden: VibeVoiceLinear
  private let endOutput: VibeVoiceLinear
  private let speechScale: MLXArray
  private let speechBias: MLXArray
  private let latentDimensions: Int

  init(configuration: VibeVoiceConfiguration, weights: VibeVoiceWeights) throws {
    let model = configuration.transformer
    latentDimensions = configuration.codec.latentDimensions
    embedding = try weights.embedding(
      "language_model.embed_tokens", rows: model.vocabularySize, dimensions: model.dimensions)
    let types = try weights.embedding("tts_input_types", rows: 2, dimensions: model.dimensions)
    speechType = try types([0])
    textType = try types([1])
    textStack = try VibeVoiceTransformer(
      configuration: model, weights: weights,
      stack: .init(path: "language_model", layerCount: model.layers - configuration.speechLayers))
    speechStack = try VibeVoiceTransformer(
      configuration: model, weights: weights,
      stack: .init(
        path: "tts_language_model", layerCount: configuration.speechLayers,
        finalNorm: weights.tensor("tts_language_model.norm.weight", shape: [model.dimensions])))
    diffusion = try VibeVoiceDiffusion(configuration: configuration.diffusion, weights: weights)
    connectorInput = try weights.linear(
      "acoustic_connector.fc1", input: latentDimensions, output: model.dimensions)
    connectorNorm = try weights.tensor("acoustic_connector.norm.weight", shape: [model.dimensions])
    connectorOutput = try weights.linear(
      "acoustic_connector.fc2", input: model.dimensions, output: model.dimensions)
    endHidden = try weights.linear(
      "tts_eos_classifier.fc1", input: model.dimensions, output: model.dimensions)
    endOutput = try weights.linear("tts_eos_classifier.fc2", input: model.dimensions, output: 1)
    speechScale = try weights.tensor("speech_scaling_factor", shape: [])
    speechBias = try weights.tensor("speech_bias_factor", shape: [])
    guard speechScale.item(Float.self).isFinite, speechScale.item(Float.self) > 0,
      speechBias.item(Float.self).isFinite
    else { throw VibeVoiceError.invalidTensor("speech normalization") }
  }

  func stream(
    tokens: [Int32], prompt: VibeVoicePrompt, decoder: VibeVoiceAudioDecoder,
    receive: ([Float]) throws -> Void
  ) throws {
    guard !tokens.isEmpty else { throw TTSError.invalidRequest }
    var textCache = prompt.text
    var speechCache = prompt.speech
    var negativeCache = prompt.negativeSpeech
    var positive: MLXArray?
    var negative = prompt.negativeCondition
    var textOffset = 0
    var frames = 0
    decoder.reset()
    defer { decoder.reset() }
    while frames < Self.maximumSpeechFrames {
      try Task.checkCancellation()
      if textOffset < tokens.count {
        let end = min(tokens.count, textOffset + Self.textWindow)
        let text = try textStack(embedding(Array(tokens[textOffset..<end])), caches: &textCache)
        positive = try speechStack(text + textType, caches: &speechCache)[(-1)...]
        textOffset = end
      }
      guard var condition = positive else { throw VibeVoiceError.invalidVoice }
      for _ in 0..<Self.speechWindow {
        try Task.checkCancellation()
        let latent = try diffusion.sample(
          positive: condition, negative: negative,
          noise: MLXRandom.normal([1, latentDimensions]))
        let samples = try decoder.decode(latent / speechScale - speechBias)
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 8 }) else {
          throw TTSError.invalidAudio
        }
        try receive(samples)
        frames += 1
        let acoustic =
          connectorOutput(
            MLXFast.rmsNorm(
              connectorInput(latent), weight: connectorNorm, eps: Self.connectorEpsilon))
          + speechType
        condition = try speechStack(acoustic, caches: &speechCache)
        negative = try speechStack(acoustic, caches: &negativeCache)
        if endOutput(maximum(endHidden(condition), 0)).item(Float.self) > 0 { return }
        if frames == Self.maximumSpeechFrames { throw TTSError.invalidRequest }
      }
      positive = condition
    }
  }
}
