import AppKit
import SilliesCore
import SwiftUI

struct CompanionHUDView: View {
  let model: CompanionHUDModel
  let state: CompanionBindingState
  @State private var hoveredPrimaryAction = false

  var body: some View {
    Group {
      switch state {
      case .followingFocusedWindow:
        EmptyView()

      case .active(let target, let skill, _, let statusDetail, let audioLevel):
        activeCard(
          target: target, skill: skill, statusDetail: statusDetail, audioLevel: audioLevel)

      case .completed(let target, let skill, let summary, let recordID, _):
        completedCard(
          target: target, skill: skill, summary: summary, recordID: recordID)
      }
    }
    .padding(14)
    .fixedSize()
  }

  private func activeCard(
    target: WindowTargetCandidate?, skill: CompanionSkillKind, statusDetail: String,
    audioLevel: Double
  ) -> some View {
    HStack(spacing: 9) {
      statusIndicator(for: skill, audioLevel: audioLevel)

      SessionHUDLabel(
        title: "\(skill.title) · \(target?.appName ?? "Microphone")", status: statusDetail)

      if let session = model.audioSession, skill.isAudioSession {
        AudioHUDControls(session: session, open: { model.onOpenSession?() })
      }

      if let stopTitle = skill.stopActionTitle {
        SessionHUDAction(title: stopTitle) { model.onStopSkill?() }
      }

      SessionHUDDismiss(title: "Cancel skill") {
        model.onUnbind?()
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background(SessionHUDBackground(emphasis: .active))
  }

  private func completedCard(
    target: WindowTargetCandidate?, skill: CompanionSkillKind, summary: String, recordID: UUID
  ) -> some View {
    return HStack(spacing: 9) {
      ZStack {
        Circle()
          .fill(
            completionNeedsAttention
              ? Color.orange.opacity(0.15)
              : Color(red: 0.28, green: 0.64, blue: 0.43).opacity(0.15)
          )
          .frame(width: 28, height: 28)
        Image(
          systemName: completionNeedsAttention
            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(
          completionNeedsAttention ? Color.orange : Color(red: 0.28, green: 0.64, blue: 0.43))
      }

      VStack(alignment: .leading, spacing: 1.5) {
        Text(completionHeadline(for: skill))
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(SilliesTheme.ink)
          .lineLimit(1)
        Text("\((target?.appName ?? "Microphone")) · \(summary)")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
          .lineLimit(1)
          .frame(maxWidth: 205, alignment: .leading)
      }

      if skill.offersTargetActivationOnCompletion {
        Button {
          if let target { model.onFocusWindow?(target) }
        } label: {
          Text("Focus App")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SilliesTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
      }

      Button {
        model.onOpenVault?(recordID)
      } label: {
        HStack(spacing: 3) {
          Text("Vault")
          Image(systemName: "arrow.up.right")
            .font(.system(size: 8.5, weight: .bold))
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(hoveredPrimaryAction ? Color.white : SilliesTheme.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
          Capsule().fill(
            hoveredPrimaryAction ? SilliesTheme.accent : SilliesTheme.accent.opacity(0.14))
        )
      }
      .buttonStyle(.plain)
      .onHover { hoveredPrimaryAction = $0 }
      .help("Open in Session Vault")

      if skill == .stash {
        Button("Undo") { model.onUndoStash?(recordID) }.buttonStyle(.plain).font(.caption)
      }

      SessionHUDDismiss(title: "Dismiss") {
        model.onUnbind?()
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background(SessionHUDBackground(emphasis: .completed))
  }

  private var completionNeedsAttention: Bool {
    model.persistenceError != nil || model.completedRecord?.failure != nil
  }

  private func completionHeadline(for skill: CompanionSkillKind) -> String {
    completionNeedsAttention ? "\(skill.title) Needs Attention" : skill.completionHeadline
  }

  @ViewBuilder
  private func statusIndicator(for skill: CompanionSkillKind, audioLevel: Double) -> some View {
    if skill.isAudioSession {
      SessionAudioIndicator(
        level: audioLevel, isCapturing: model.audioSession?.phase == .capturing)
    } else {
      ZStack {
        Circle()
          .fill(SilliesTheme.accent.opacity(0.14))
          .frame(width: 28, height: 28)
        Image(systemName: skill.symbolName)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(SilliesTheme.accent)
      }
    }
  }
}
