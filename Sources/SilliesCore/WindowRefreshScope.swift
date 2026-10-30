/// Metadata reads during manipulation must stay restricted to the tracked window.
public enum WindowRefreshScope: Sendable {
  case trackedWindow, applicationWindows

  public enum Interaction: Sendable { case idle, manipulatingWindow }

  public func merging(_ pending: WindowRefreshScope?, during interaction: Interaction) -> Self {
    if interaction == .manipulatingWindow { return .trackedWindow }
    return self == .applicationWindows || pending == .applicationWindows
      ? .applicationWindows : .trackedWindow
  }
}
