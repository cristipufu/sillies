/// Local, content-free measurements returned by the native runtime for bounded benchmarks.
package struct TextGenerationMetrics: Codable, Sendable {
  package struct Tokens: Sendable {
    package let processedPrompt: Int
    package let cachedPrompt: Int
    package let generated: Int
    package init(processedPrompt: Int, cachedPrompt: Int, generated: Int) {
      self.processedPrompt = processedPrompt
      self.cachedPrompt = cachedPrompt
      self.generated = generated
    }
  }
  package struct Timing: Sendable {
    package let prompt: Double
    package let generation: Double
    package init(prompt: Double, generation: Double) {
      self.prompt = prompt
      self.generation = generation
    }
  }
  package let processedPromptTokens: Int
  package let cachedPromptTokens: Int
  package let generatedTokens: Int
  package let promptSeconds: Double
  package let generationSeconds: Double

  package init(tokens: Tokens, timing: Timing) {
    processedPromptTokens = tokens.processedPrompt
    cachedPromptTokens = tokens.cachedPrompt
    generatedTokens = tokens.generated
    promptSeconds = timing.prompt
    generationSeconds = timing.generation
  }
}
