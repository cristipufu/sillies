/// The companion that produced an artifact and the application it came from.
public struct SessionOrigin: Sendable {
  public struct Source: Sendable {
    public let appName: String
    public let bundleIdentifier: String?
    public let windowTitle: String?

    public init(appName: String, bundleIdentifier: String? = nil, windowTitle: String? = nil) {
      self.appName = appName
      self.bundleIdentifier = bundleIdentifier
      self.windowTitle = windowTitle
    }
  }

  public let characterID: String
  public let characterName: String
  public let source: Source

  public init(characterID: String, characterName: String, source: Source) {
    self.characterID = characterID
    self.characterName = characterName
    self.source = source
  }
}
