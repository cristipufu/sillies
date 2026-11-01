import Foundation
import Observation
import SilliesDesign

/// UI language is independent of recognition, writing output, and companion speech.
@MainActor @Observable final class LanguagePreferences {
  typealias Loader = @Sendable (URL) async throws -> [InterfaceLanguage]
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
  @ObservationIgnored private let load: Loader
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var loading: Task<Void, Never>?
  var isLoading: Bool { loading != nil }

  init(
    defaults: UserDefaults = .standard,
    metadataURL: URL? = Bundle.main.url(
      forResource: "Languages", withExtension: "json"),
    load: @escaping Loader = { file in
      try await Task.detached(priority: .utility) { try LanguageCatalog.load(from: file) }.value
    }
  ) {
    self.defaults = defaults
    self.metadataURL = metadataURL
    self.load = load
    launchSelection = defaults.string(forKey: Self.selectionKey) ?? Self.systemID
    selectedID = launchSelection
  }

  func start() {
    guard loading == nil, languages.isEmpty else { return }
    guard let metadataURL else {
      error = CocoaError(.fileNoSuchFile).localizedDescription
      return
    }
    let token = UUID()
    generation = token
    loading = Task { [weak self, load] in
      defer { if self?.generation == token { self?.loading = nil } }
      do {
        let languages = try await load(metadataURL)
        try Task.checkCancellation()
        guard self?.generation == token else { return }
        self?.languages = languages
        self?.error = nil
        if let self, selectedID != Self.systemID,
          !languages.contains(where: { $0.code == selectedID })
        {
          select(Self.systemID)
        }
      } catch {
        guard !Task.isCancelled, self?.generation == token else { return }
        self?.error = String(
          localized: "Language choices could not be loaded. Please reopen Settings.")
        fputs("Language catalog failed: \(error)\n", stderr)
      }
    }
  }

  func stop() {
    generation = UUID()
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
