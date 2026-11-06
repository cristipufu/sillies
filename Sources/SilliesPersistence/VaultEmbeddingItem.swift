/// A passage revision awaiting a vector from the selected search provider.
public struct VaultEmbeddingItem: Sendable {
  public let id: String
  public let revision: String
  public let text: String
}
