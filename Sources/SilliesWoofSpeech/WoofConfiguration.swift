import Foundation

/// The published archive describes its network independently of the app's model catalog.
struct WoofConfiguration: Decodable {
  struct Speech: Decodable {
    let transformer: Transformer
    let layers: [WoofSpeechLayerParameters]
    let conditioning: WoofLinearParameter
    let adaptiveModulation: WoofLinearParameter
    let flowBlocks: [WoofFlowBlockParameters]
    let latentInput: WoofLinearParameter
    let flowInput: WoofLinearParameter
    let flowOutput: WoofLinearParameter
    let textEmbedding: WoofTensorReference
    let beginningOfSpeech: WoofTensorReference

    enum CodingKeys: String, CodingKey {
      case transformer = "cfg"
      case layers
      case conditioning = "ce"
      case adaptiveModulation = "ada"
      case flowBlocks = "hblocks"
      case latentInput = "lat_in"
      case flowInput = "h_inp"
      case flowOutput = "h_out"
      case textEmbedding = "text_emb"
      case beginningOfSpeech = "bos"
    }
  }

  struct Transformer: Decodable {
    let layerCount: Int
    let dimensions: Int
    let heads: Int
    let feedForwardDimensions: Int
    let flowDimensions: Int
    let flowDepth: Int
    let latentDimensions: Int
    let rotaryBase: Float

    enum CodingKeys: String, CodingKey {
      case layerCount = "L"
      case dimensions = "d"
      case heads = "H"
      case feedForwardDimensions = "ff"
      case flowDimensions = "hw"
      case flowDepth = "depth"
      case latentDimensions = "latent"
      case rotaryBase = "rope_base"
    }

    func validate() throws {
      guard (1...32).contains(layerCount), (1...64).contains(heads),
        (1...2_048).contains(dimensions), dimensions.isMultiple(of: heads * 2),
        (1...8_192).contains(feedForwardDimensions), (1...2_048).contains(flowDimensions),
        (1...16).contains(flowDepth), (1...128).contains(latentDimensions),
        latentDimensions.isMultiple(of: 16), rotaryBase.isFinite, rotaryBase > 1
      else { throw WoofModelError.invalidConfiguration }
    }
  }

  struct Decoder: Decodable {
    struct Attention: Decodable {
      let heads: Int
      let headDimensions: Int
      let window: Int
      let epsilon: Float
      enum CodingKeys: String, CodingKey {
        case heads
        case headDimensions = "head_dim"
        case window
        case epsilon = "eps"
      }

      func validate() throws {
        guard (1...32).contains(heads), (2...256).contains(headDimensions),
          headDimensions.isMultiple(of: 2), (1...1_024).contains(window),
          epsilon.isFinite, epsilon > 0, epsilon < 1
        else { throw WoofModelError.invalidConfiguration }
      }
    }

    struct Layer: Decodable {
      let attentionNorm: WoofAffineParameters
      let feedForwardNorm: WoofAffineParameters
      let queryKeyValue: WoofTensorParameter
      let attentionOutput: WoofTensorParameter
      let feedForwardInput: WoofTensorParameter
      let feedForwardOutput: WoofTensorParameter

      enum CodingKeys: String, CodingKey {
        case attentionNorm = "ln1"
        case feedForwardNorm = "ln2"
        case queryKeyValue = "qkv"
        case attentionOutput = "o"
        case feedForwardInput = "fc1"
        case feedForwardOutput = "fc2"
      }
    }

    let attention: Attention
    let input: WoofAffineParameters
    let inverseFrequencies: WoofTensorReference
    let layers: [Layer]
    let convolutions: [WoofDecoderOperation]

    enum CodingKeys: String, CodingKey {
      case attention = "cfg"
      case input = "inp"
      case inverseFrequencies = "inv_freq"
      case layers = "tf"
      case convolutions = "seanet"
    }
  }

  let speech: Speech
  let decoder: Decoder
  let mean: WoofTensorReference
  let standardDeviation: WoofTensorReference
  let voices: [String: WoofTensorReference]
  let maximumFrames: Int
  let framesPerSecond: Float

  enum CodingKeys: String, CodingKey {
    case speech, decoder, mean, voices
    case standardDeviation = "std"
    case maximumFrames = "max_frames"
    case framesPerSecond = "fps"
  }

  static let maximumContext = 1_100
  static let sampleRate = 24_000
  static let frameRate = 25
  static let samplesPerFrame = sampleRate / frameRate

  func validate() throws {
    try speech.transformer.validate()
    try decoder.attention.validate()
    guard speech.layers.count == speech.transformer.layerCount,
      speech.flowBlocks.count == speech.transformer.flowDepth,
      (1...8).contains(decoder.layers.count),
      (1...32).contains(decoder.convolutions.count),
      !voices.isEmpty, voices.count <= 16, (1...750).contains(maximumFrames),
      framesPerSecond == Float(Self.frameRate)
    else { throw WoofModelError.invalidConfiguration }
  }
}
