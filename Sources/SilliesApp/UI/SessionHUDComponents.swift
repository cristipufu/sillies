import SwiftUI

/// The compact session controls shared by recording, dictation, and selection editing.
struct SessionHUDBackground: View {
  enum Emphasis { case active, completed }
  let emphasis: Emphasis
  var body: some View {
    RoundedRectangle(cornerRadius: 15, style: .continuous)
      .fill(SilliesTheme.card.opacity(0.98))
      .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
      .overlay(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .strokeBorder(
            emphasis == .active ? SilliesTheme.accent.opacity(0.5) : SilliesTheme.border,
            lineWidth: emphasis == .active ? 1.1 : 0.8))
  }
}

struct SessionHUDLabel: View {
  let title: String
  let status: String
  var body: some View {
    VStack(alignment: .leading, spacing: 1.5) {
      Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(SilliesTheme.ink)
      Text(status).font(.system(size: 10, weight: .medium)).monospacedDigit()
        .foregroundStyle(SilliesTheme.secondary)
    }.lineLimit(1).frame(width: 210, alignment: .leading).help(status)
  }
}

struct SessionHUDAction: View {
  let title: String
  let action: () -> Void
  @State private var hovered = false
  var body: some View {
    Button(action: action) {
      Text(title).font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
        .background(
          Capsule().fill(hovered ? SilliesTheme.accent.opacity(0.85) : SilliesTheme.accent))
    }.buttonStyle(.plain).onHover { hovered = $0 }
  }
}

struct SessionHUDDismiss: View {
  let title: String
  let action: () -> Void
  @State private var hovered = false
  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(hovered ? SilliesTheme.ink : SilliesTheme.secondary)
        .frame(width: 20, height: 20)
        .background(Circle().fill(hovered ? SilliesTheme.border : SilliesTheme.soft))
    }.buttonStyle(.plain).onHover { hovered = $0 }.help(title).accessibilityLabel(title)
  }
}

struct SessionAudioIndicator: View {
  private static let minimumHeight: CGFloat = 4
  private static let maximumHeight: CGFloat = 14
  private static let gain: Double = 11
  private static let sideFactor: Double = 0.65
  let level: Double
  let isCapturing: Bool
  private var color: Color { isCapturing ? .red : SilliesTheme.secondary }
  var body: some View {
    ZStack {
      Circle().fill(color.opacity(0.14)).frame(width: 28, height: 28)
      HStack(spacing: 2) {
        ForEach(0..<3, id: \.self) { index in
          let factor = index == 1 ? 1.0 : Self.sideFactor
          RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.88))
            .frame(
              width: 2.5,
              height: max(
                Self.minimumHeight,
                min(Self.maximumHeight, Self.minimumHeight + CGFloat(level * Self.gain * factor))))
        }
      }
    }.accessibilityLabel(isCapturing ? "Microphone listening" : "Microphone inactive")
  }
}
