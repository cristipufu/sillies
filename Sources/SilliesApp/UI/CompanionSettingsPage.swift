import SwiftUI

struct CompanionSettingsPage: View {
  @Environment(\.silliesTheme) private var theme
  let controller: CompanionController
  var body: some View {
    @Bindable var settings = controller.settings
    SettingsCard(title: String(localized: "Where they hang out")) {
      Toggle("Follow the active window", isOn: $settings.followsWindows)
      Text(
        "Companions stay outside your document, along window edges. Turn this off to keep them on the desktop."
      )
      .font(.caption).foregroundStyle(theme.secondary)
      Divider()
      Picker("Energy", selection: $settings.activity) {
        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      Text(
        settings.activity == .playful
          ? String(
            localized: "Little dances, shared adventures, and the occasional bit of mischief.")
          : String(localized: "A quieter crew, with fewer interruptions.")
      )
      .font(.caption).foregroundStyle(theme.secondary)
      HStack {
        Text("Size")
        Slider(value: $settings.size, in: AppSettings.minSize...AppSettings.maxSize)
          .accessibilityLabel("Companion size")
        Text("\(Int(settings.size))").monospacedDigit().foregroundStyle(theme.secondary)
      }
      Toggle("Reduce motion", isOn: $settings.reduceMotion)
      Text(
        "Gentler expressions and still perches. Your Mac’s Reduce Motion setting is also respected."
      )
      .font(.caption).foregroundStyle(theme.secondary)
      if !controller.tracker.hasAccessibility {
        Divider()
        Button("Enable enhanced app reactions…") {
          controller.tracker.requestAccessibility()
          if !controller.tracker.hasAccessibility { controller.tracker.openAccessibilitySettings() }
        }.buttonStyle(SoftButtonStyle())
        Text(
          "Optional Accessibility access adds app context. Following window edges already works without it."
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }
    }
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Your crew").font(.system(.headline, design: .rounded))
        Spacer()
        Text("\(settings.enabledCharacters.count) selected").font(.caption).foregroundStyle(
          theme.secondary)
      }
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12
      ) {
        ForEach(controller.catalog.characters) { character in
          CompanionCharacterCard(
            character: character,
            enabled: settings.enabledCharacters.contains(character.id),
            registry: controller.renderers
          ) {
            settings.toggleCharacter(character.id)
          }
        }
      }
    }
    SettingsCard(
      title: String(localized: "Apps where they take a break"),
      detail: String(localized: "Hide the crew in apps where you want a little more space.")
    ) {
      HStack {
        Text(controller.tracker.applicationName).fontWeight(.medium)
        Spacer()
        Button(
          controller.isExcluded ? String(localized: "Show here") : String(localized: "Hide here")
        ) {
          controller.toggleCurrentApplicationExclusion()
        }.buttonStyle(SoftButtonStyle()).disabled(controller.tracker.bundleIdentifier == nil)
      }
      ForEach(settings.excludedApplications.sorted(), id: \.self) { bundle in
        HStack {
          Text(bundle).font(.caption).lineLimit(1)
          Spacer()
          Button("Remove") { settings.excludedApplications.remove(bundle) }.buttonStyle(.link)
            .accessibilityLabel("Show companions in \(bundle)")
        }
      }
    }
  }
}
