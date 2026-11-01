import Foundation

enum LocalizationFixtures {
  static func verify() -> Bool {
    let fixtures: [(String, Bool)] = [
      (#"Text("Hello")"#, true),
      (#"Text(verbatim: "Model-ID")"#, true),
      (#"Text(active ? String(localized: "On") : String(localized: "Off"))"#, true),
      (#"Text(active ? "On" : "Off")"#, false),
      (#"SettingsCard(title: "Settings") {}"#, false),
      (#"SettingsCard(title: String(localized: "Settings")) {}"#, true),
      (#"var title: String { "Settings" }"#, false),
      (#"var errorDescription: String? { "Could not save." }"#, false),
      (#"var id: String { "saved-record" }"#, true),
      (#"Image(systemName: "mic.fill")"#, true),
      (#"Text("\(name): \(state)")"#, true),
    ]
    for (source, valid) in fixtures {
      let diagnostics = LocalizationVisitor.check(
        source: source, path: "Sources/SilliesApp/UI/Fixture.swift")
      guard diagnostics.isEmpty == valid else {
        fputs("Localization fixture failed: \(source)\n", stderr)
        return false
      }
    }
    print("Localization: \(fixtures.count) syntax fixtures passed.")
    return true
  }
}
