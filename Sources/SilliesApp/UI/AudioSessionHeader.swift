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
    SessionIdentityHeader(title: model.kind.title, symbol: model.kind.symbolName) {
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
    } accessory: {
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
    if model.transcriptionFailure != nil, model.phase == .capturing {
      return "Recording · Transcription stopped"
    }
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
      if model.kind.isMeetingSession {
        Text(
          "Includes your microphone and saves both sides of the conversation. Speaker echo is reduced locally. Muting Meet or Zoom does not mute Sillies."
        )
      }
      Text("Sillies does not change your meeting’s microphone, mute, volume, or audio routing.")
        .foregroundStyle(SilliesTheme.secondary)
      if let maximumSpeakers = model.diarizationModel?.capabilities.maximumSpeakers {
        Text(
          "Speaker labels distinguish up to \(maximumSpeakers) voices per source. Speaker numbers belong to this meeting and source; a microphone speaker and a meeting speaker with the same number are not necessarily the same person. Check labels before relying on them."
        )
      }
    }.font(.callout).padding(18).frame(width: 320)
  }
}
