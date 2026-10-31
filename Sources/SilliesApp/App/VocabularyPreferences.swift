import Foundation
import Observation
import SilliesCore
import Synchronization

@MainActor @Observable
final class VocabularyPreferences {
  private static let key = "personalDictionary.v1"
  private(set) var entries: [VocabularyEntry]
  private(set) var error: String?
  private let defaults: UserDefaults
  @ObservationIgnored nonisolated private let current = Mutex(PersonalDictionary(entries: []))

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    entries = []
    if let data = defaults.data(forKey: Self.key) {
      do { entries = try JSONDecoder().decode([VocabularyEntry].self, from: data) } catch {
        self.error = "Could not load your dictionary."
        fputs("Dictionary load failed: \(error)\n", stderr)
      }
    }
    current.withLock { $0 = PersonalDictionary(entries: entries) }
  }

  nonisolated func snapshot() -> PersonalDictionary { current.withLock { $0 } }

  func add(phrase: String, heardAs: String) {
    let entry = VocabularyEntry(phrase: phrase, heardAs: heardAs)
    guard !entry.phrase.isEmpty, entries.count < PersonalDictionary.maximumEntries,
      entry.phrase.count <= PersonalDictionary.maximumPhraseLength,
      entry.heardAs.count <= PersonalDictionary.maximumPhraseLength
    else {
      error = "Use up to 100 entries, with at most 100 characters per phrase."
      return
    }
    guard !entries.contains(where: { $0.phrase == entry.phrase && $0.heardAs == entry.heardAs })
    else { return }
    entries.append(entry)
    save()
  }

  func remove(_ id: UUID) {
    entries.removeAll { $0.id == id }
    save()
  }

  private func save() {
    current.withLock { $0 = PersonalDictionary(entries: entries) }
    do {
      defaults.set(try JSONEncoder().encode(entries), forKey: Self.key)
      error = nil
    } catch {
      self.error = "Could not save your dictionary."
      fputs("Dictionary save failed: \(error)\n", stderr)
    }
  }
}
