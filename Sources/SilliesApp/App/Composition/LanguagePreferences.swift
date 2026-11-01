import Foundation
import Observation
import SilliesDesign

/// UI language is independent of recognition, writing output, and companion speech.
@MainActor @Observable final class LanguagePreferences {
  static let systemID = "system"
  private static let preferenceKey = "AppleLanguages"
  private static let selectionKey = "interfaceLanguage"
  private(set) var languages: [InterfaceLanguage] = []
  private(set) var error: String?
  private(set) var selectedID: String
  var requiresRestart: Bool { selectedID != launchSelection }
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let launchSelection: String
  @ObservationIgnored private let metadataURL: URL?
  @ObservationIgnored private var loading: Task<Void, Never>?

  init(
    defaults: UserDefaults = .standard,
    metadataURL: URL? = Bundle.main.url(
      forResource: "Languages", withExtension: "json")
  ) {
    self.defaults = defaults
    self.metadataURL = metadataURL
    launchSelection = defaults.string(forKey: Self.selectionKey) ?? Self.systemID
    selectedID = launchSelection
  }

  func start() {
    guard loading == nil, languages.isEmpty else { return }
    guard let metadataURL else {
      error = CocoaError(.fileNoSuchFile).localizedDescription
      return
    }
    loading = Task { [weak self] in
      defer { self?.loading = nil }
      do {
        let languages = try await Task.detached(priority: .utility) {
          try LanguageCatalog.load(from: metadataURL)
        }.value
        try Task.checkCancellation()
        self?.languages = languages
        self?.error = nil
        if let self, selectedID != Self.systemID,
          !languages.contains(where: { $0.code == selectedID })
        {
          select(Self.systemID)
        }
      } catch {
        guard !Task.isCancelled else { return }
        self?.error = String(
          localized: "Language choices could not be loaded. Please reopen Settings.")
        fputs("Language catalog failed: \(error)\n", stderr)
      }
    }
  }

  func stop() {
    loading?.cancel()
    loading = nil
  }

  func select(_ id: String) {
    guard id == Self.systemID || languages.contains(where: { $0.code == id }) else {
      return
    }
    selectedID = id
    defaults.set(selectedID, forKey: Self.selectionKey)
    if selectedID == Self.systemID {
      defaults.removeObject(forKey: Self.preferenceKey)
    } else {
      defaults.set([selectedID], forKey: Self.preferenceKey)
    }
  }
}
