import SilliesCore
import SwiftUI

struct AudioSessionHeader: View {
  let model: AudioSessionPresentation
  @State private var showsSourceDetails = false

  var body: some View {
    VStack(spacing: 18) {
      identityRow
      controlsRow
    }
  }

  private var identityRow: some View {
    HStack(spacing: 12) {
      Image(systemName: model.kind.symbolName)
        .font(.system(size: 22, weight: .medium)).foregroundStyle(SilliesTheme.accent)
        .frame(width: 48, height: 48)
        .background(SilliesTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text(model.kind.title).font(.system(size: 24, weight: .bold, design: .rounded))
        HStack(spacing: 6) {
          Text(model.sourceLabel).lineLimit(1).truncationMode(.middle)
          Button {
            showsSourceDetails.toggle()
          } label: {
            Image(systemName: "info.circle")
          }
          .buttonStyle(.plain).accessibilityLabel("About these audio sources")
          .popover(isPresented: $showsSourceDetails) { sourceDetails }
        }
        .font(.callout).foregroundStyle(SilliesTheme.secondary)
      }
      Spacer(minLength: 12)
      Text(SessionRecord.formatDuration(model.elapsed))
        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
        .accessibilityLabel("Session duration: \(SessionRecord.formatDuration(model.elapsed))")
    }
  }

  private var controlsRow: some View {
    HStack(spacing: 10) {
      HStack(spacing: 7) {
        Circle().fill(model.phase == .capturing ? Color.red : SilliesTheme.secondary)
          .frame(width: 7, height: 7)
        Text(statusTitle).font(.callout.weight(.medium))
      }
      Spacer(minLength: 8)
      if model.canPause {
        Button(
          model.isPaused ? "Resume" : "Pause",
          systemImage: model.isPaused ? "play.fill" : "pause.fill"
        ) {
          if model.isPaused { model.onResume?() } else { model.onPause?() }
        }.buttonStyle(SoftButtonStyle())
      }
      if model.canFinish {
        Button("Finish & Save", systemImage: "stop.fill") { model.onFinish?() }
          .buttonStyle(.borderedProminent).controlSize(.large)
      } else if let id = model.savedRecordID {
        Button("Open in Vault", systemImage: "tray") { model.onOpenRecord?(id) }
          .buttonStyle(.borderedProminent).controlSize(.large)
      } else {
        ProgressView().controlSize(.small)
        Text("Saving…").font(.callout).foregroundStyle(SilliesTheme.secondary)
      }
    }
  }

  private var statusTitle: String {
    if model.pendingLanguageID != nil { return "Changing language…" }
    switch model.phase {
    case .preparing:
      if model.isLoadingLanguages { return "Getting ready" }
      return model.selectedLanguageID == nil ? "Choose a language" : "Preparing speech…"
    case .capturing: return model.kind == .record ? "Recording" : "Listening"
    case .paused: return "Paused"
    case .finishing: return "Finishing session"
    case .finished: return "Saved to Vault"
    case .failed: return "Session stopped"
    }
  }

  private var sourceDetails: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Audio sources").font(.headline)
      Text(
        model.kind == .record
          ? "Records your laptop microphone when available and saves a playable audio file."
          : "Captures audio from the selected app, including other tabs in the same browser.")
      if model.kind == .participate {
        Text(
          "Your microphone is included and labeled separately. Muting Meet or Zoom does not mute Sillies. Use headphones to prevent speaker audio from entering both streams; use Listen for meeting audio alone."
        )
      }
      Text("Sillies does not change your meeting’s microphone, mute, volume, or audio routing.")
        .foregroundStyle(SilliesTheme.secondary)
    }.font(.callout).padding(18).frame(width: 320)
  }
}
