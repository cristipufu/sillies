import Foundation
import Observation

enum SetupActivity: String, CaseIterable, Identifiable {
  case chat, talk, meetings, companions
  var id: Self { self }
  var title: String {
    switch self {
    case .chat: String(localized: "Chat")
    case .talk: String(localized: "Talk")
    case .meetings: String(localized: "Meetings")
    case .companions: String(localized: "Companions")
    }
  }
  var symbol: String {
    switch self {
    case .chat: "text.bubble"
    case .talk: "waveform"
    case .meetings: "person.2.wave.2"
    case .companions: "pawprint"
    }
  }
  var detail: String {
    switch self {
    case .chat: String(localized: "A little conversation, whenever you like.")
    case .talk: String(localized: "Speak naturally. Your companion talks back.")
    case .meetings: String(localized: "Listen, take notes and keep the useful bits.")
    case .companions: String(localized: "A little company. No models or permissions needed.")
    }
  }
}

/// Small persisted state machine; closing setup never discards the user's choices.
@MainActor @Observable final class SetupJourney {
  enum Step: String, CaseIterable {
    case companion, activity, preparation
    var title: String {
      switch self {
      case .companion: String(localized: "Your companion")
      case .activity: String(localized: "Your day")
      case .preparation: String(localized: "Your setup")
      }
    }
  }
  private static let key = "setupJourney"
  private struct Saved: Codable {
    var companionID: String?
    var activity: String?
    var step: String?
    var introduced: Bool
    var completed: Bool
  }
  private(set) var companionID: String
  private(set) var activity: SetupActivity
  private(set) var step: Step
  private(set) var introduced: Bool
  private(set) var completed: Bool
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let availableIDs: Set<String>

  init(defaults: UserDefaults, availableIDs: [String]) {
    self.defaults = defaults
    self.availableIDs = Set(availableIDs)
    let saved: Saved?
    do {
      saved = try defaults.data(forKey: Self.key).map {
        try JSONDecoder().decode(Saved.self, from: $0)
      }
    } catch {
      saved = nil
      fputs("Setup preferences: \(error)\n", stderr)
    }
    companionID =
      saved?.companionID.flatMap { availableIDs.contains($0) ? $0 : nil }
      ?? availableIDs.first ?? ""
    activity = saved?.activity.flatMap(SetupActivity.init(rawValue:)) ?? .chat
    step = saved?.step.flatMap(Step.init(rawValue:)) ?? .companion
    introduced = saved?.introduced ?? false
    completed = saved?.completed ?? false
  }

  func chooseCompanion(_ id: String) {
    guard availableIDs.contains(id) else { return }
    companionID = id
    save()
  }
  func chooseActivity(_ value: SetupActivity) {
    activity = value
    save()
  }
  func move(to step: Step) {
    self.step = step
    save()
  }
  func deferSetup() {
    introduced = true
    save()
  }
  func complete() {
    completed = true
    introduced = true
    save()
  }
  func reopen() {
    completed = false
    save()
  }

  private func save() {
    do {
      let saved = Saved(
        companionID: companionID, activity: activity.rawValue, step: step.rawValue,
        introduced: introduced, completed: completed)
      defaults.set(try JSONEncoder().encode(saved), forKey: Self.key)
    } catch { fputs("Setup preferences could not be saved: \(error)\n", stderr) }
  }
}
