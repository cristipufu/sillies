/// Tasks choose an intent; native adapters translate it into their supported sampling options.
package enum TextGenerationStyle: String, Codable, Sendable {
  case precise, conversation

  package var temperature: Double { self == .conversation ? 0.7 : 0 }
  package var probabilityThreshold: Double { self == .conversation ? 0.9 : 1 }
  package var repetitionPenalty: Float? { self == .conversation ? 1.08 : nil }
  package var repetitionContextSize: Int { 64 }
}
