import SilliesCore

/// Owns the selected writing companion and its reservation; clocks remain with the crew owner.
@MainActor final class WritingCompanionSelection {
  struct Activation {
    let companion: CompanionInstance
    let state: BehaviorState?
  }
  private weak var selected: CompanionInstance?
  var companionID: String? { selected?.definition.id }
  var anchor: WritingCompanionAnchor? {
    guard let selected, selected.isAttachmentVisible else { return nil }
    return selected.writingAnchor
  }

  func isAvailable(in companions: [CompanionInstance]) -> Bool {
    selected != nil || companions.contains(where: \.isAvailableForWriting)
  }

  func begin(in companions: [CompanionInstance], at time: Double) -> Activation? {
    if let selected { return Activation(companion: selected, state: nil) }
    guard let companion = companions.filter(\.isAvailableForWriting).randomElement() else {
      return nil
    }
    selected = companion
    return Activation(companion: companion, state: companion.beginWritingIndicator(at: time))
  }

  func finish() -> Activation? {
    guard let selected else { return nil }
    return Activation(companion: selected, state: selected.finishWritingIndicator())
  }

  func end() {
    selected?.endWritingIndicator()
    selected = nil
  }
}
