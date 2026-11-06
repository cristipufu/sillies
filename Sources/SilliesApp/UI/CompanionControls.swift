import SwiftUI

/// The same immediate crew preferences in the menu-bar panel and Settings.
struct CompanionControls: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var settings: AppSettings

  private static let rowSpacing: CGFloat = 14
  private static let columnSpacing: CGFloat = 18

  var body: some View {
    Grid(
      alignment: .leading, horizontalSpacing: Self.columnSpacing, verticalSpacing: Self.rowSpacing
    ) {
      GridRow {
        Text("Size")
        sizeSlider
      }
      GridRow {
        Text("Energy")
        FillWidthSegmentedPicker(
          selection: $settings.activity,
          choices: ActivityLevel.allCases.map { .init(value: $0, title: $0.title) },
          label: String(localized: "Energy")
        )
        .frame(maxWidth: .infinity)
        .help(
          settings.activity == .playful
            ? String(
              localized: "Little dances, shared adventures, and the occasional bit of mischief.")
            : String(localized: "A quieter crew, with fewer interruptions.")
        )
        .accessibilityIdentifier("crew-energy")
      }
      GridRow {
        Text("Position")
        FillWidthSegmentedPicker(
          selection: $settings.followsWindows,
          choices: [
            .init(value: true, title: String(localized: "Active window")),
            .init(value: false, title: String(localized: "Desktop")),
          ],
          label: String(localized: "Position")
        )
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("crew-position")
      }
    }
    .font(.callout)
    .tint(theme.accent)
  }

  private var sizeSlider: some View {
    Slider(
      value: $settings.size, in: AppSettings.minSize...AppSettings.maxSize,
      step: AppSettings.sizeStep,
      label: { Text("Companion size") },
      tick: { SliderTick($0) }
    )
    .labelsHidden()
    .accessibilityIdentifier("crew-size")
  }
}
