import AppKit
import SilliesCore
import SwiftUI

struct CompanionHUDView: View {
  @Environment(\.silliesTheme) private var theme
  let model: CompanionHUDModel
  let state: CompanionBindingState
  @State private var hoveredPrimaryAction = false
  private static let cardInset: CGFloat = 14

  var body: some View {
    Group {
      switch state {
      case .followingFocusedWindow:
        EmptyView()

      case .active(_, let skill, _, let statusDetail, _):
        if skill == .chat, let conversation = model.conversation, conversation.mode == .talk {
          TalkHUDView(
            model: conversation, openTranscript: { model.onOpenSession?() },
            openSettings: { model.onOpenChatSettings?($0) }
          )
        } else if skill.isAudioSession {
          RecordingHUDView(model: model, state: state)
        } else {
          activeCard(skill: skill, statusDetail: statusDetail)
        }

      case .completed(let target, let skill, let summary, let recordID, _):
        completedCard(
          target: target, skill: skill, summary: summary, recordID: recordID
        )
      }
    }
    .padding(
      .horizontal,
      surface == .speechBubble
        ? CompanionSpeechBubbleLayout.tailDepth + CompanionSpeechBubbleLayout.shadowInset
        : Self.cardInset
    )
    .padding(
      .vertical,
      surface == .speechBubble ? CompanionSpeechBubbleLayout.shadowInset : Self.cardInset
    )
    .fixedSize()
  }

  private var surface: CompanionHUDModel.Surface { model.surface(for: state) }

  private func activeCard(skill: CompanionSkillKind, statusDetail: String) -> some View {
    HStack(spacing: 9) {
      statusIndicator(for: skill)

      SessionHUDLabel(
        title:
          "\(skill.title) · \(model.sourceName(for: state))",
        status: statusDetail)

      if skill == .chat {
        SessionHUDAction(title: String(localized: "Open Chat")) { model.onOpenSession?() }
      }

      if let stopTitle = skill.stopActionTitle {
        SessionHUDAction(title: stopTitle) { model.onStopSkill?() }
      }

      SessionHUDDismiss(title: String(localized: "Cancel skill")) {
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
              ? theme.warning.opacity(0.15)
              : theme.success.opacity(0.15)
          )
          .frame(width: 28, height: 28)
        Image(
          systemName: completionNeedsAttention
            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(
          completionNeedsAttention ? theme.warning : theme.success)
      }

      VStack(alignment: .leading, spacing: 1.5) {
        Text(completionHeadline(for: skill))
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(theme.ink)
          .lineLimit(1)
        Text(
          "\(model.sourceName(for: state)) · \(summary)"
        )
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.secondary)
        .lineLimit(1)
        .frame(maxWidth: 205, alignment: .leading)
      }

      if skill.offersTargetActivationOnCompletion {
        Button {
          if let target { model.onFocusWindow?(target) }
        } label: {
          Text("Focus App")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(theme.accentFill, in: Capsule())
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
        .foregroundStyle(hoveredPrimaryAction ? theme.onAccent : theme.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
          Capsule().fill(
            hoveredPrimaryAction ? theme.accentFill : theme.accent.opacity(0.14))
        )
      }
      .buttonStyle(.plain)
      .onHover { hoveredPrimaryAction = $0 }
      .help("Open in Session Vault")

      if skill == .stash {
        Button("Undo") { model.onUndoStash?(recordID) }.buttonStyle(.plain).font(.caption)
      }

      SessionHUDDismiss(title: String(localized: "Dismiss")) {
        model.onUnbind?()
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background {
      if surface == .card { SessionHUDBackground(emphasis: .completed) }
    }
  }

  private var completionNeedsAttention: Bool {
    model.persistenceError != nil || model.completedRecord?.failure != nil
  }

  private func completionHeadline(for skill: CompanionSkillKind) -> String {
    completionNeedsAttention
      ? String(localized: "\(skill.title) Needs Attention") : skill.completionHeadline
  }

  private func statusIndicator(for skill: CompanionSkillKind) -> some View {
    ZStack {
      Circle()
        .fill(theme.accent.opacity(0.14))
        .frame(width: 28, height: 28)
      Image(systemName: skill.symbolName)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(theme.accent)
    }
  }
}
