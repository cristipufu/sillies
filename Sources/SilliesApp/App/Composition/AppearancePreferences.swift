import AppKit
import Observation
import SilliesDesign

enum ApplicationAppearance: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: Self { self }
  var title: String {
    switch self {
    case .system: String(localized: "System")
    case .light: String(localized: "Light")
    case .dark: String(localized: "Dark")
    }
  }
  var native: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

/// Preferences own selection; the design target owns validated, immutable palettes.
@MainActor @Observable final class AppearancePreferences {
  private static let themeKey = "colorTheme"
  private static let appearanceKey = "appearance"
  var appearance: ApplicationAppearance {
    didSet {
      defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
      apply()
    }
  }
  var themeID: String {
    didSet {
      defaults.set(themeID, forKey: Self.themeKey)
      apply()
    }
  }
  private(set) var themes: [ThemeDefinition] = []
  private(set) var error: String?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var loading: Task<Void, Never>?
  @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
  @ObservationIgnored var onChange: (() -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    appearance =
      ApplicationAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
    themeID = defaults.string(forKey: Self.themeKey) ?? ThemeCatalog.defaultID
  }
  var selectedTheme: ThemeDefinition? {
    themes.first { $0.id == themeID } ?? themes.first { $0.id == ThemeCatalog.defaultID }
  }
  func load() async {
    guard themes.isEmpty else { return }
    do {
      let themes = try await Task.detached(priority: .utility) { try ThemeCatalog.loadBundled() }
        .value
      try Task.checkCancellation()
      self.themes = themes
      error = nil
      apply()
    } catch {
      guard !Task.isCancelled else { return }
      self.error = error.localizedDescription
      fputs("Theme catalog failed: \(error)\n", stderr)
    }
  }
  func start() {
    if accessibilityObserver == nil {
      accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.apply() }
      }
    }
    guard loading == nil else { return }
    loading = Task { [weak self] in await self?.load() }
  }
  func stop() {
    loading?.cancel()
    loading = nil
    if let accessibilityObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
      self.accessibilityObserver = nil
    }
  }
  private func apply() {
    onChange?()
  }
}
