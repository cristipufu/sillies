import AppKit
import Observation

enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
  case calm, playful
  var id: Self { self }
  var title: String { self == .calm ? "Calm" : "Playful" }
  var multiplier: Double { self == .calm ? 0.55 : 1 }
}

@MainActor @Observable
final class AppSettings {
  static let minSize: Double = 48
  static let maxSize: Double = 112
  static let defaultSize: Double = 64
  static let largeSizeThreshold: Double = 90
  static let defaultCharacterIDs = ["mochi", "kiko"]

  var enabledCharacters: Set<String> {
    didSet {
      save()
      onChange?()
    }
  }
  var size: Double {
    didSet {
      save()
      onChange?()
    }
  }
  var activity: ActivityLevel {
    didSet {
      save()
      onChange?()
    }
  }
  var followsWindows: Bool {
    didSet {
      save()
      onChange?()
    }
  }
  var paused = false { didSet { onChange?() } }
  var excludedApplications: Set<String> {
    didSet {
      save()
      onChange?()
    }
  }
  var reduceMotion: Bool {
    didSet {
      save()
      onChange?()
    }
  }
  @ObservationIgnored var onChange: (() -> Void)?
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    enabledCharacters = Set(
      defaults.stringArray(forKey: "characters") ?? Self.defaultCharacterIDs)
    let storedSize = defaults.double(forKey: "size")
    size =
      storedSize > 0
      ? min(max(storedSize, Self.minSize), Self.maxSize) : Self.defaultSize
    activity = ActivityLevel(rawValue: defaults.string(forKey: "activity") ?? "") ?? .playful
    followsWindows = defaults.object(forKey: "followsWindows") as? Bool ?? true
    excludedApplications = Set(defaults.stringArray(forKey: "excludedApplications") ?? [])
    reduceMotion = defaults.bool(forKey: "reduceMotion")
  }

  func toggleCharacter(_ id: String) {
    if enabledCharacters.contains(id) {
      enabledCharacters.remove(id)
    } else {
      enabledCharacters.insert(id)
    }
  }

  private func save() {
    defaults.set(enabledCharacters.sorted(), forKey: "characters")
    defaults.set(size, forKey: "size")
    defaults.set(activity.rawValue, forKey: "activity")
    defaults.set(followsWindows, forKey: "followsWindows")
    defaults.set(excludedApplications.sorted(), forKey: "excludedApplications")
    defaults.set(reduceMotion, forKey: "reduceMotion")
  }
}
