import FoundationModels
import SilliesTextModels

enum AppleGenerationOptions {
  static func make(_ request: TextGenerationRequest) -> GenerationOptions {
    let task = request.style.settings(in: AppleConversationPolicy.generation)
    let sampling = task.sampling
    let outputTokens = min(request.maximumTokens, task.outputTokens)
    // Apple's tool decoder can fail under stochastic sampling even on a first-turn greeting.
    // Keep native tool selection/arguments deterministic; personality still comes from instructions.
    if !request.tools.isEmpty {
      return GenerationOptions(samplingMode: .greedy, maximumResponseTokens: outputTokens)
    }
    return GenerationOptions(
      samplingMode: request.style == .conversation
        ? .random(probabilityThreshold: Double(sampling.topP)) : .greedy,
      temperature: Double(sampling.temperature), maximumResponseTokens: outputTokens)
  }
}
