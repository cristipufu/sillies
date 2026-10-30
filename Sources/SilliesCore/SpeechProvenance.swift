/// Identifies the engine and exact model revision used to produce a saved transcript.
public struct SpeechProvenance: Codable, Equatable, Sendable {
  public let providerID: String
  public let modelID: String
  public let revision: String
  public let modelName: String

  public init(providerID: String, modelID: String, revision: String, modelName: String) {
    self.providerID = providerID
    self.modelID = modelID
    self.revision = revision
    self.modelName = modelName
  }
}
