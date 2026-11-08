import Foundation

/// The supported streaming architecture, validated before creating native tensor operations.
struct VibeVoiceConfiguration: Decodable {
  struct Transformer: Decodable {
    let dimensions: Int
    let feedForwardDimensions: Int
    let attentionHeads: Int
    let keyValueHeads: Int
    let layers: Int
    let maximumContext: Int
    let vocabularySize: Int
    let normalizationEpsilon: Float
    let rotaryBase: Float
    let activation: String
    let slidingWindow: Bool
    var headDimensions: Int { dimensions / attentionHeads }

    enum CodingKeys: String, CodingKey {
      case dimensions = "hidden_size"
      case feedForwardDimensions = "intermediate_size"
      case attentionHeads = "num_attention_heads"
      case keyValueHeads = "num_key_value_heads"
      case layers = "num_hidden_layers"
      case maximumContext = "max_position_embeddings"
      case vocabularySize = "vocab_size"
      case normalizationEpsilon = "rms_norm_eps"
      case rotaryBase = "rope_theta"
      case activation = "hidden_act"
      case slidingWindow = "use_sliding_window"
    }
  }

  struct Codec: Decodable {
    let latentDimensions: Int
    let channels: Int
    let filters: Int
    let ratios: [Int]
    let encoderDepths: String
    let decoderDepths: String?
    let causal: Bool
    let padding: String
    let normalization: String
    let normalizationEpsilon: Float
    let mixer: String
    let lastNormDisabled: Bool
    let convolutionBias: Bool
    let convolutionNorm: String
    let affineNormalization: Bool
    var depths: [Int] {
      if let decoderDepths { return decoderDepths.split(separator: "-").compactMap { Int($0) } }
      return encoderDepths.split(separator: "-").compactMap { Int($0) }.reversed()
    }

    enum CodingKeys: String, CodingKey {
      case latentDimensions = "vae_dim"
      case channels
      case filters = "decoder_n_filters"
      case ratios = "decoder_ratios"
      case encoderDepths = "encoder_depths"
      case decoderDepths = "decoder_depths"
      case causal
      case padding = "pad_mode"
      case normalization = "layernorm"
      case normalizationEpsilon = "layernorm_eps"
      case mixer = "mixer_layer"
      case lastNormDisabled = "disable_last_norm"
      case convolutionBias = "conv_bias"
      case convolutionNorm = "conv_norm"
      case affineNormalization = "layernorm_elementwise_affine"
    }
  }

  struct Diffusion: Decodable {
    let dimensions: Int
    let latentDimensions: Int
    let layers: Int
    let expansion: Float
    let trainingSteps: Int
    let schedule: String
    let prediction: String
    let normalizationEpsilon: Float

    enum CodingKeys: String, CodingKey {
      case dimensions = "hidden_size"
      case latentDimensions = "latent_size"
      case layers = "head_layers"
      case expansion = "head_ffn_ratio"
      case trainingSteps = "ddpm_num_steps"
      case schedule = "ddpm_beta_schedule"
      case prediction = "prediction_type"
      case normalizationEpsilon = "rms_norm_eps"
    }
  }

  struct Quantization: Decodable {
    let bits: Int
    let groupSize: Int
    let mode: String
    var isSupported: Bool { [4, 8].contains(bits) && groupSize == 64 && mode == "affine" }
    enum CodingKeys: String, CodingKey {
      case bits
      case groupSize = "group_size"
      case mode
    }
  }

  let architecture: String
  let transformer: Transformer
  let speechLayers: Int
  let codec: Codec
  let diffusion: Diffusion
  let quantization: Quantization
  enum CodingKeys: String, CodingKey {
    case architecture = "model_type"
    case transformer = "decoder_config"
    case speechLayers = "tts_backbone_num_hidden_layers"
    case codec = "acoustic_tokenizer_config"
    case diffusion = "diffusion_head_config"
    case quantization
  }

  // This runtime implements the published 0.5B architecture; new families need explicit validation.
  func validate() throws {
    guard architecture == "vibevoice_streaming", transformer.dimensions == 896,
      transformer.feedForwardDimensions == 4_864, transformer.attentionHeads == 14,
      transformer.keyValueHeads == 2, transformer.layers == 24, speechLayers == 20,
      transformer.maximumContext == 8_192, transformer.vocabularySize == 151_936,
      transformer.normalizationEpsilon == 1e-6, transformer.rotaryBase == 1_000_000,
      transformer.activation == "silu", !transformer.slidingWindow,
      codec.latentDimensions == 64, codec.channels == 1, codec.filters == 32,
      codec.ratios == [8, 5, 5, 4, 2, 2], codec.depths == [8, 3, 3, 3, 3, 3, 3],
      codec.causal, codec.padding == "constant", codec.normalization == "RMSNorm",
      codec.normalizationEpsilon == 1e-5, codec.mixer == "depthwise_conv", codec.lastNormDisabled,
      codec.convolutionBias, codec.convolutionNorm == "none", codec.affineNormalization,
      diffusion.dimensions == transformer.dimensions,
      diffusion.latentDimensions == codec.latentDimensions,
      diffusion.layers == 4, diffusion.expansion == 3, diffusion.trainingSteps == 1_000,
      diffusion.schedule == "cosine", diffusion.prediction == "v_prediction",
      diffusion.normalizationEpsilon == 1e-5,
      quantization.isSupported
    else { throw VibeVoiceError.unsupportedConfiguration }
  }
}
