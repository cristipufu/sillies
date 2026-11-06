import Foundation
import Observation
import SilliesCore

/// Manual profile editing never invokes the model or fabricates a conversation source message.
@MainActor @Observable package final class ChatPersonalFacts {
  package private(set) var facts: [PersonalFact] = []
  package private(set) var failure: String?
  package var isSaving: Bool { mutation.isRunning }
  package private(set) var isEditing = false
  package var topic = ""
  package var value = ""
  package var scope = PersonalFact.Scope.companion
  package var canChange: @MainActor () -> Bool = { true }
  private let history: ChatHistory
  private let repository: (any PersonalFactsRepository)?
  private var selected: PersonalFact?
  private var generation = UUID()
  private let mutation = ChatPersistenceOperation<PersonalFactsSnapshot>()
  package var isAvailable: Bool { repository != nil }
  package var canSave: Bool {
    isEditing && !isSaving && canChange() && history.handle != nil
      && MemoryFact(key: topic, value: value).isValid
      && value.count <= PersonalFact.maximumValueCharacters
  }

  package init(history: ChatHistory, repository: (any PersonalFactsRepository)?) {
    self.history = history
    self.repository = repository
  }

  package func load() async {
    guard !isSaving, let repository, let handle = history.handle else { return }
    let token = UUID()
    generation = token
    do {
      let snapshot = try await repository.personalFacts(handle)
      try Task.checkCancellation()
      guard generation == token, history.handle == handle else { return }
      facts = snapshot.facts
      failure = nil
    } catch is CancellationError {
    } catch {
      guard generation == token else { return }
      failure = error.localizedDescription
    }
  }

  package func begin(_ fact: PersonalFact? = nil) {
    guard !isSaving, canChange() else { return }
    selected = fact
    topic = fact?.fact.key ?? ""
    value = fact?.fact.value ?? ""
    scope = fact?.scope ?? .companion
    failure = nil
    isEditing = true
  }

  package var canChooseScope: Bool { selected == nil }
  package func cancelEditing() {
    guard !isSaving else { return }
    isEditing = false
    selected = nil
    topic = ""
    value = ""
  }

  package func save() async {
    guard canSave, let repository, let handle = history.handle else { return }
    let write = PersonalFactWrite(
      handle: handle, scope: scope, fact: .init(key: topic, value: value), replacing: selected)
    let token = UUID()
    generation = token
    do {
      _ = try await mutation.run(
        { try await repository.savePersonalFact(write) },
        accept: { [weak self] result in
          guard let self, self.history.handle == handle else { return }
          self.facts = result.facts
          self.failure = nil
          self.isEditing = false
          self.selected = nil
        })
    } catch is CancellationError {
    } catch { if generation == token { failure = error.localizedDescription } }
  }

  package func remove(_ fact: PersonalFact) async {
    guard !isSaving, canChange(), let repository, let handle = history.handle else { return }
    let token = UUID()
    generation = token
    do {
      let result = try await mutation.run {
        try await repository.removePersonalFact(fact, handle: handle)
      }
      guard generation == token, history.handle == handle else { return }
      facts = result.facts
      failure = nil
    } catch is CancellationError {
    } catch { if generation == token { failure = error.localizedDescription } }
  }

  package func stop() { generation = UUID() }

  package func finish(
    deliver: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
    completion: @escaping @MainActor @Sendable () -> Void
  ) {
    stop()
    mutation.finish(deliver: deliver, completion: completion)
  }
}
