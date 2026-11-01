import FoundationModels
import SilliesTextModels

enum AppleGenerationOptions {
  static func make(_ request: TextGenerationRequest) -> GenerationOptions {
    // Apple's tool decoder can fail under stochastic sampling even on a first-turn greeting.
    // Keep native tool selection/arguments deterministic; personality still comes from instructions.
    if !request.tools.isEmpty {
      return GenerationOptions(samplingMode: .greedy, maximumResponseTokens: request.maximumTokens)
    }
    return GenerationOptions(
      samplingMode: request.style == .conversation
        ? .random(probabilityThreshold: request.style.probabilityThreshold) : .greedy,
      temperature: request.style.temperature, maximumResponseTokens: request.maximumTokens)
  }
}
