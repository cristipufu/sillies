import Observation

@MainActor @Observable final class VaultNavigation {
  enum Section { case captures, conversations }
  enum Editor: Identifiable {
    case stash, retention
    var id: Self { self }
  }
  var section = Section.captures
  var editor: Editor?
}
