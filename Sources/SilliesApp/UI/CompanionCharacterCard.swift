import SilliesCore
import SwiftUI

struct CompanionCharacterCard: View {
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
              enabled ? SilliesTheme.accent : SilliesTheme.secondary.opacity(0.4)
            )
            .padding(9)
        }.frame(height: 111)
        Text(character.name).font(.system(size: 14, weight: .bold, design: .rounded)).padding(
          .top, 5)
        Text(character.subtitle).font(.system(size: 9)).foregroundStyle(SilliesTheme.secondary)
          .lineLimit(1).minimumScaleFactor(0.85)
      }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 17))
        .overlay(
          RoundedRectangle(cornerRadius: 17).strokeBorder(
            enabled ? SilliesTheme.accent.opacity(0.45) : SilliesTheme.border,
            lineWidth: enabled ? 1.3 : 0.7))
    }.buttonStyle(.plain)
      .accessibilityLabel("\(character.name), \(character.subtitle)")
      .accessibilityValue(enabled ? "Enabled" : "Disabled")
      .help(character.bio)
  }
}
