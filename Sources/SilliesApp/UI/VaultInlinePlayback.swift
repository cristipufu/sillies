import SilliesCore
import SwiftUI

struct VaultInlinePlayback: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: RecordingPlaybackModel
  var body: some View {
    HStack(spacing: 12) {
      Button(action: model.togglePlayback) {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
      }
      .buttonStyle(.plain).foregroundStyle(theme.accent)
      .accessibilityLabel(
        model.isPlaying ? String(localized: "Pause recording") : String(localized: "Play recording")
      )
      Slider(
        value: Binding(get: { model.position }, set: model.seek), in: 0...max(1, model.duration)
      ).accessibilityLabel("Playback position")
      Text(
        "\(SessionRecord.formatDuration(model.position)) / \(SessionRecord.formatDuration(model.duration))"
      )
      .font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.secondary)
      Menu {
        ForEach(RecordingPlaybackModel.rates, id: \.self) { value in
          Button("\(value.formatted())×") { model.setRate(value) }
        }
      } label: {
        Text("\(model.rate.formatted())×").font(.caption).monospacedDigit()
      }
      .menuStyle(.borderlessButton).fixedSize().help("Playback speed")
    }.padding(16).background(theme.soft)
  }
}
