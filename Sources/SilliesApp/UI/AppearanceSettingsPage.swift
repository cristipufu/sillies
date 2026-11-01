import SilliesDesign
import SwiftUI

struct AppearanceSettingsPage: View {
  @Bindable var model: AppearancePreferences
  @Environment(\.colorScheme) private var colorScheme
  private static let previewHeight: CGFloat = 68

  var body: some View {
    SettingsCard(
      title: String(localized: "Appearance"),
      detail: String(localized: "Follow your Mac, or choose the light that suits you.")
    ) {
      Picker("Appearance", selection: $model.appearance) {
        ForEach(ApplicationAppearance.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented).labelsHidden()
    }
    SettingsCard(
      title: String(localized: "Color theme"),
      detail: String(localized: "The same little companions, with a different mood.")
    ) {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
        ForEach(model.themes) { theme in themeButton(theme) }
      }
      if let error = model.error {
        Text(error).textSelection(.enabled).foregroundStyle(SilliesTheme.danger)
      }
      Text("Themes work in both Light and Dark. Increase Contrast uses native macOS colors.")
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
    }.task { await model.load() }
  }

  private func themeButton(_ theme: ThemeDefinition) -> some View {
    let palette = colorScheme == .dark ? theme.dark : theme.light
    let selected = model.selectedTheme?.id == theme.id
    return Button {
      model.themeID = theme.id
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 7).fill(previewColor(palette, .soft)).frame(width: 35)
          VStack(alignment: .leading, spacing: 7) {
            Capsule().fill(previewColor(palette, .ink)).frame(width: 48, height: 5)
            Capsule().fill(previewColor(palette, .secondary)).frame(width: 76, height: 4)
            HStack {
              Spacer()
              Capsule().fill(previewColor(palette, .accentFill)).frame(width: 52, height: 14)
            }
          }.padding(8)
        }.padding(10).frame(height: Self.previewHeight).background(
          previewColor(palette, .paper), in: RoundedRectangle(cornerRadius: 10))
        HStack {
          Text(verbatim: theme.name).font(
            .system(.callout, design: .rounded).weight(.semibold))
          Spacer()
          Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(
            selected ? SilliesTheme.accent : SilliesTheme.secondary)
        }
      }.padding(12).background(
        SilliesTheme.soft.opacity(selected ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14).strokeBorder(
          selected ? SilliesTheme.accent : SilliesTheme.border))
    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func previewColor(_ palette: ThemePalette, _ role: ThemeColorRole) -> Color {
    guard let color = palette[role] else { return SilliesTheme.paper }
    return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
  }
}
