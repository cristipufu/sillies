import SilliesCore
import SwiftUI

struct DictationSessionView: View {
  let model: DictationCoordinator
  let companionName: String
  let copy: (String) -> Void
  let history: () -> Void

  var body: some View {
    @Bindable var session = model
    VStack(alignment: .leading, spacing: SessionWindowLayout.spacing) {
      SessionIdentityHeader(title: "Dictate", symbol: "mic.fill") {
        Text("\(companionName) · Into \(model.applicationName)").lineLimit(1)
      } accessory: {
        Text(SessionRecord.formatDuration(model.elapsed))
          .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
      }
      controls
      if let failure = model.recoveryFailure { SessionFailureNotice(failure: failure) }
      if let result = model.result, !result.notice.isEmpty {
        Text(result.notice).font(.callout).foregroundStyle(SilliesTheme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      SessionTranscriptCard(
        text: model.preview, isFinished: !model.isActive,
        followsLive: $session.followsLiveTranscript
      ) {
        VStack(spacing: 10) {
          Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(SilliesTheme.accent)
          Text(model.phase == .listening ? "Ready for your words" : "Getting ready to listen")
            .font(.callout.weight(.medium))
          Text("Your words will appear here as you speak.")
            .font(.caption).foregroundStyle(SilliesTheme.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
      }
      Label(
        "On this Mac · Audio isn’t saved. Closing this window keeps dictation running.",
        systemImage: "lock.shield"
      ).font(.caption).foregroundStyle(SilliesTheme.secondary)
    }
    .padding(SessionWindowLayout.padding)
    .frame(
      minWidth: SessionWindowLayout.minimumSize.width,
      minHeight: SessionWindowLayout.minimumSize.height
    )
    .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
    .environment(\.controlActiveState, .active)
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Circle().fill(model.phase == .listening ? Color.red : SilliesTheme.secondary)
        .frame(width: 7, height: 7)
      Text(model.status).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      if model.isActive {
        Button("Cancel") { model.cancel() }.buttonStyle(SoftButtonStyle())
        if model.canFinish {
          Button(
            model.canInsert ? "Finish & Insert" : "Finish", systemImage: "stop.fill"
          ) {
            model.finish()
          }.buttonStyle(.borderedProminent).controlSize(.large)
        }
      } else {
        Button("Recent writing", action: history).buttonStyle(SoftButtonStyle())
        if let result = model.result {
          Button("Copy text", systemImage: "doc.on.doc") { copy(result.text) }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
      }
    }
  }
}
