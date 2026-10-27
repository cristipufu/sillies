import AppKit
import SilliesCore
import SwiftUI

@MainActor @Observable
final class CompanionHUDModel {
  var state: CompanionBindingState = .followingFocusedWindow
  var onSelectSkill: ((CompanionSkillKind) -> Void)?
  var onStopSkill: (() -> Void)?
  var onUnbind: (() -> Void)?
  var onOpenVault: ((UUID) -> Void)?
  var onFocusWindow: ((WindowTargetCandidate) -> Void)?
}

struct CompanionHUDView: View {
  private static let minAudioBarHeight: CGFloat = 4.0
  private static let maxAudioBarHeight: CGFloat = 14.0
  private static let audioBarGain: Double = 11.0
  private static let sideAudioBarFactor: Double = 0.65

  let model: CompanionHUDModel
  @State private var hoveredSkill: CompanionSkillKind?
  @State private var hoveredPrimaryAction = false
  @State private var hoveredDismiss = false

  var body: some View {
    Group {
      switch model.state {
      case .followingFocusedWindow:
        EmptyView()

      case .awaitingSelection(let target, _):
        selectionCard(for: target)

      case .active(let target, let skill, _, let statusDetail, let audioLevel):
        activeCard(
          target: target, skill: skill, statusDetail: statusDetail, audioLevel: audioLevel)

      case .completed(let target, let skill, let summary, let recordID, _):
        completedCard(
          target: target, skill: skill, summary: summary, recordID: recordID)
      }
    }
    .padding(14)
  }

  private func selectionCard(for target: WindowTargetCandidate) -> some View {
    HStack(spacing: 6) {
      HStack(spacing: 6) {
        appIcon(for: target, fallbackSymbol: "macwindow")
        Text(target.appName)
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(SilliesTheme.ink)
          .lineLimit(1)
          .frame(maxWidth: 110)
      }
      .padding(.trailing, 2)

      Divider().frame(height: 16)

      ForEach(CompanionSkillKind.radialSkills) { skill in
        let isHovered = hoveredSkill == skill
        Button {
          model.onSelectSkill?(skill)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: skill.symbolName)
              .font(.system(size: 10.5, weight: .semibold))
            Text(skill.shortTitle)
              .font(.system(size: 10.5, weight: .bold, design: .rounded))
          }
          .padding(.horizontal, 9)
          .padding(.vertical, 5.5)
          .background(
            Capsule()
              .fill(isHovered ? SilliesTheme.accent : SilliesTheme.soft)
          )
          .foregroundStyle(isHovered ? Color.white : SilliesTheme.ink)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          hoveredSkill = hovering ? skill : (hoveredSkill == skill ? nil : hoveredSkill)
        }
        .help(skill.title)
      }

      dismissButton(helpText: "Unpin from window") {
        model.onUnbind?()
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(hudCardBackground(accentBorder: false))
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

  @ViewBuilder
  private func appIcon(for target: WindowTargetCandidate, fallbackSymbol: String) -> some View {
    if let icon = ApplicationIconCache.shared.image(for: target) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(SilliesTheme.accent.opacity(0.14))
          .frame(width: 18, height: 18)
        Image(systemName: fallbackSymbol)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(SilliesTheme.accent)
      }
    }
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

@MainActor
final class CompanionHUDController {
  private static let fallbackSize = CGSize(width: 340, height: 64)
  private static let minPanelWidth: CGFloat = 220
  private static let minPanelHeight: CGFloat = 52
  private static let headTopOffsetFactor: Double = 0.78
  private static let horizontalScreenInset: CGFloat = 6
  private static let bottomScreenInset: CGFloat = 6
  private static let topScreenInset: CGFloat = 2
  nonisolated private static let asciiZeroScalar: UInt32 = 0x30
  nonisolated private static let asciiNineScalar: UInt32 = 0x39

  private enum LayoutKey: Equatable {
    case hidden
    case selection(appName: String, displayTitle: String)
    case active(skill: CompanionSkillKind, appName: String, normalizedDetail: String)
    case completed(skill: CompanionSkillKind, appName: String, summary: String)

    init(_ state: CompanionBindingState) {
      switch state {
      case .followingFocusedWindow:
        self = .hidden
      case .awaitingSelection(let target, _):
        self = .selection(appName: target.appName, displayTitle: target.displayTitle)
      case .active(let target, let skill, _, let statusDetail, _):
        self = .active(
          skill: skill, appName: target.appName,
          normalizedDetail: Self.normalizeMonospacedDigits(statusDetail))
      case .completed(let target, let skill, let summary, _, _):
        self = .completed(skill: skill, appName: target.appName, summary: summary)
      }
    }

    /// Status labels use `.monospacedDigit()`, so digit-only timer changes (`00:12` -> `00:13`)
    /// preserve exact glyph width while any text or character change invalidates cached sizing.
    private static func normalizeMonospacedDigits(_ text: String) -> String {
      var scalars = String.UnicodeScalarView()
      scalars.reserveCapacity(text.unicodeScalars.count)
      for scalar in text.unicodeScalars {
        if scalar.value >= CompanionHUDController.asciiZeroScalar
          && scalar.value <= CompanionHUDController.asciiNineScalar
        {
          scalars.append("0")
        } else {
          scalars.append(scalar)
        }
      }
      return String(scalars)
    }
  }

  let model = CompanionHUDModel()
  private var panel: SkillFloatingPanel?
  private var hostingView: NSHostingView<CompanionHUDView>?
  private var lastLayoutKey: LayoutKey?
  private var cachedPanelSize: CGSize?
  private(set) var layoutMeasurements = 0
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }
  var currentPanelSize: CGSize? { panel?.frame.size }

  func update(
    state: CompanionBindingState, companionPoint: CGPoint, characterSize: Double,
    visibleFrame: CGRect
  ) {
    if model.state != state { model.state = state }
    if let target = state.boundTarget { ApplicationIconCache.shared.prepare(for: target) }
    guard state.isBound else {
      hide()
      return
    }
    ensurePanelCreated(for: state)
    updatePanelLevel(for: state)
    let panelSize = resolvePanelSize(for: state)
    let frame = clampedFrame(
      for: panelSize, companionPoint: companionPoint, characterSize: characterSize,
      visibleFrame: visibleFrame)
    if panel?.frame != frame { panel?.setFrame(frame, display: false) }
    if panel?.isVisible != true {
      panel?.orderFrontRegardless()
    }
  }

  func hide() {
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    hostingView = nil
    lastLayoutKey = nil
    cachedPanelSize = nil
  }

  private func ensurePanelCreated(for state: CompanionBindingState) {
    guard panel == nil else { return }
    let host = NSHostingView(rootView: CompanionHUDView(model: model))
    let created = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.fallbackSize),
      ignoresMouseEvents: false,
      level: CompanionPanel.hudLevel(forWindowLayer: state.boundTarget?.windowLayer ?? 0))
    created.contentView = host
    hostingView = host
    panel = created
    lastLayoutKey = nil
    cachedPanelSize = nil
  }

  private func updatePanelLevel(for state: CompanionBindingState) {
    let targetHUDLevel = CompanionPanel.hudLevel(
      forWindowLayer: state.boundTarget?.windowLayer ?? 0)
    if panel?.level != targetHUDLevel {
      panel?.level = targetHUDLevel
    }
  }

  private func resolvePanelSize(for state: CompanionBindingState) -> CGSize {
    let key = LayoutKey(state)
    if key == lastLayoutKey, let cachedPanelSize {
      return cachedPanelSize
    }
    layoutMeasurements += 1
    hostingView?.rootView = CompanionHUDView(model: model)
    hostingView?.invalidateIntrinsicContentSize()
    hostingView?.layoutSubtreeIfNeeded()
    let fitting = hostingView?.fittingSize ?? Self.fallbackSize
    let measured = CGSize(
      width: max(Self.minPanelWidth, ceil(fitting.width)),
      height: max(Self.minPanelHeight, ceil(fitting.height)))
    lastLayoutKey = key
    cachedPanelSize = measured
    return measured
  }

  private func clampedFrame(
    for panelSize: CGSize, companionPoint: CGPoint, characterSize: Double, visibleFrame: CGRect
  ) -> CGRect {
    let headTopOffset = characterSize * Self.headTopOffsetFactor
    let unclampedX = companionPoint.x - panelSize.width / 2
    let clampedX = min(
      max(unclampedX, visibleFrame.minX + Self.horizontalScreenInset),
      visibleFrame.maxX - panelSize.width - Self.horizontalScreenInset)
    let preferredY = companionPoint.y + headTopOffset
    let clampedY = min(
      max(preferredY, visibleFrame.minY + Self.bottomScreenInset),
      visibleFrame.maxY - panelSize.height - Self.topScreenInset)
    return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
  }
}
