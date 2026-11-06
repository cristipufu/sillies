import Foundation
import Observation

/// App-owned reading preference; fixtures use the explicit in-memory initializer.
@MainActor @Observable final class ChatReadingPreferences {
  private static let key = "chatMessageSize"
  var size: ChatReadingSize { didSet { save(size) } }
  @ObservationIgnored private let save: (ChatReadingSize) -> Void

  init(defaults: UserDefaults) {
    size = defaults.string(forKey: Self.key).flatMap(ChatReadingSize.init(rawValue:)) ?? .standard
    save = { defaults.set($0.rawValue, forKey: Self.key) }
  }
  init(size: ChatReadingSize) {
    self.size = size
    save = { _ in }
  }
}
