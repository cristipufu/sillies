import SwiftUI

struct CompanionSettingsPage: View {
  @Environment(\.silliesTheme) private var theme
  let controller: CompanionController

  var body: some View {
    crewSection
    behaviorSection
    exclusionsSection
  }

  private var crewSection: some View {
    let settings = controller.settings
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your crew").font(.system(.headline, design: .rounded))
        Spacer()
        Text("\(settings.enabledCharacters.count) selected")
          .font(.caption.weight(.medium)).foregroundStyle(theme.accent)
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(theme.accent.opacity(0.09), in: Capsule())
      }
      CompanionGrid(columns: .four, spacing: 12) {
        ForEach(controller.catalog.characters) { character in
          CompanionCharacterCard(
            character: character,
            isSelected: settings.enabledCharacters.contains(character.id),
            registry: controller.renderers, presentation: .gallery
          ) {
            settings.toggleCharacter(character.id)
          }
        }
      }
    }
  }

  private var behaviorSection: some View {
    @Bindable var settings = controller.settings
    return SettingsCard(title: String(localized: "Where they hang out")) {
      CompanionControls(settings: settings)
      Divider()
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
  }

  private var exclusionsSection: some View {
    let settings = controller.settings
    return SettingsCard(
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
