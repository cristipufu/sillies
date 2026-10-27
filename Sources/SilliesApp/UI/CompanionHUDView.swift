import AppKit
import SilliesCore
import SwiftUI

struct CompanionHUDView: View {
  private static let minAudioBarHeight: CGFloat = 4.0
  private static let maxAudioBarHeight: CGFloat = 14.0
  private static let audioBarGain: Double = 11.0
  private static let sideAudioBarFactor: Double = 0.65

  let model: CompanionHUDModel
  let state: CompanionBindingState
  @State private var hoveredPrimaryAction = false
  @State private var hoveredDismiss = false

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
    target: WindowTargetCandidate, skill: CompanionSkillKind, statusDetail: String,
    audioLevel: Double
  ) -> some View {
    HStack(spacing: 9) {
      statusIndicator(for: skill, audioLevel: audioLevel)

      VStack(alignment: .leading, spacing: 1.5) {
        Text("\(skill.title) · \(target.appName)")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(SilliesTheme.ink)
          .lineLimit(1)
        Text(statusDetail)
          .font(.system(size: 10, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(SilliesTheme.secondary)
          .lineLimit(1)
          .frame(maxWidth: 210, alignment: .leading)
      }

      if let stopTitle = skill.stopActionTitle {
        Button {
          model.onStopSkill?()
        } label: {
          Text(stopTitle)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
              Capsule().fill(
                hoveredPrimaryAction ? SilliesTheme.accent.opacity(0.85) : SilliesTheme.accent)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredPrimaryAction = $0 }
      }

      dismissButton(helpText: "Cancel skill") {
        model.onUnbind?()
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background(hudCardBackground(accentBorder: true))
  }

  private func completedCard(
    target: WindowTargetCandidate, skill: CompanionSkillKind, summary: String, recordID: UUID
  ) -> some View {
    let needsPermission = SessionRecord.indicatesPermissionNeeded(summary)
    return HStack(spacing: 9) {
      ZStack {
        Circle()
          .fill(
            needsPermission
              ? Color.orange.opacity(0.15)
              : Color(red: 0.28, green: 0.64, blue: 0.43).opacity(0.15)
          )
          .frame(width: 28, height: 28)
        Image(
          systemName: needsPermission ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(
          needsPermission ? Color.orange : Color(red: 0.28, green: 0.64, blue: 0.43))
      }

      VStack(alignment: .leading, spacing: 1.5) {
        Text(completionHeadline(for: skill, needsPermission: needsPermission))
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(SilliesTheme.ink)
          .lineLimit(1)
        Text("\(target.appName) · \(summary)")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
          .lineLimit(1)
          .frame(maxWidth: 205, alignment: .leading)
      }

      if skill.offersTargetActivationOnCompletion {
        Button {
          model.onFocusWindow?(target)
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

      dismissButton(helpText: "Dismiss") {
        model.onUnbind?()
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background(hudCardBackground(accentBorder: false))
  }

  private func completionHeadline(for skill: CompanionSkillKind, needsPermission: Bool) -> String {
    needsPermission ? "\(skill.title) Needs Access" : skill.completionHeadline
  }

  private func dismissButton(helpText: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(hoveredDismiss ? SilliesTheme.ink : SilliesTheme.secondary)
        .frame(width: 20, height: 20)
        .background(
          Circle().fill(hoveredDismiss ? SilliesTheme.border : SilliesTheme.soft)
        )
    }
    .buttonStyle(.plain)
    .onHover { hoveredDismiss = $0 }
    .help(helpText)
  }

  private func hudCardBackground(accentBorder: Bool) -> some View {
    RoundedRectangle(cornerRadius: 15, style: .continuous)
      .fill(SilliesTheme.card.opacity(0.98))
      .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
      .overlay(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .strokeBorder(
            accentBorder ? SilliesTheme.accent.opacity(0.5) : SilliesTheme.border,
            lineWidth: accentBorder ? 1.1 : 0.8)
      )
  }

  @ViewBuilder
  private func statusIndicator(for skill: CompanionSkillKind, audioLevel: Double) -> some View {
    if skill == .listen {
      ZStack {
        Circle()
          .fill(Color.red.opacity(0.14))
          .frame(width: 28, height: 28)
        HStack(spacing: 2) {
          ForEach(0..<3, id: \.self) { index in
            let factor = index == 1 ? 1.0 : Self.sideAudioBarFactor
            let barHeight = max(
              Self.minAudioBarHeight,
              min(
                Self.maxAudioBarHeight,
                Self.minAudioBarHeight + CGFloat(audioLevel * Self.audioBarGain * factor)))
            RoundedRectangle(cornerRadius: 1.5)
              .fill(Color.red.opacity(0.88))
              .frame(width: 2.5, height: barHeight)
          }
        }
      }
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
