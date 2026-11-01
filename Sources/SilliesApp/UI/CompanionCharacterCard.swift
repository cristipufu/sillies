import SilliesCore
import SwiftUI

struct CompanionCharacterCard: View {
  @Environment(\.silliesTheme) private var theme
  let character: CharacterDefinition
  let enabled: Bool
  let registry: RendererRegistry
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 5) {
        ZStack(alignment: .topTrailing) {
          RoundedRectangle(cornerRadius: 12).fill(
            Color(hex: character.accent).opacity(enabled ? 0.13 : 0.05))
          CharacterPortrait(renderer: character.renderer, size: 72, registry: registry)
            .frame(width: 100, height: 96).frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(enabled ? 1 : 0.4)
          Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15)).foregroundStyle(
              enabled ? theme.accent : theme.secondary.opacity(0.4)
            )
            .padding(9)
        }.frame(height: 111)
        Text(character.name).font(.system(size: 14, weight: .bold, design: .rounded)).padding(
          .top, 5)
        Text(LocalizedCatalogText.value(character.subtitle)).font(.system(size: 10))
          .foregroundStyle(
            theme.secondary
          )
          .lineLimit(2).frame(minHeight: 26, alignment: .topLeading)
      }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 17))
        .overlay(
          RoundedRectangle(cornerRadius: 17).strokeBorder(
            enabled ? theme.accent.opacity(0.45) : theme.border,
            lineWidth: enabled ? 1.3 : 0.7))
    }.buttonStyle(.plain)
      .accessibilityLabel("\(character.name), \(LocalizedCatalogText.value(character.subtitle))")
      .accessibilityValue(enabled ? String(localized: "Enabled") : String(localized: "Disabled"))
      .help(LocalizedCatalogText.value(character.bio))
  }
}
