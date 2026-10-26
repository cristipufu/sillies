import AppKit
import QuartzCore
import SilliesCore
import SwiftUI

/// Non-activating floating panel used for the window drop highlight, radial skill wheel, and status HUDs.
/// WindowServer shadow is disabled so SwiftUI renders crisp, unclipped shadows without rectangular backing halos.
@MainActor
final class SkillFloatingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(contentRect: CGRect, ignoresMouseEvents: Bool, level: NSWindow.Level = .statusBar) {
    super.init(
      contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    animationBehavior = .none
    self.level = level
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    self.ignoresMouseEvents = ignoresMouseEvents
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    animationBehavior = .none
    let isUnitTest =
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.arguments.contains {
        $0.contains("swift-testing") || $0.hasSuffix(".xctest")
      }
    if isUnitTest { alphaValue = 0 }
  }
}

/// Build and render the two shared overlays once, before drag interaction is enabled.
@MainActor
private enum SkillOverlayPreparation {
  static let target = WindowTargetCandidate(
    windowID: 0, processID: 0, appName: "Window",
    frame: CGRect(x: 0, y: 0, width: 480, height: 320))

  static func render(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
    }
  }
}

@MainActor @Observable
final class WindowDropHighlightModel {
  var target: WindowTargetCandidate?
  var hoveredSkill: CompanionSkillKind?
}

struct WindowDropHighlightView: View {
  let model: WindowDropHighlightModel

  var body: some View {
    HStack(spacing: 6) {
      if let target = model.target {
        if let skill = model.hoveredSkill {
          Image(systemName: skill.symbolName).font(.system(size: 11, weight: .bold))
          Text("\(skill.title) · \(target.appName)")
            .font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
        } else {
          if let icon = ApplicationIconCache.shared.image(for: target) {
            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
          } else {
            Image(systemName: "macwindow").font(.system(size: 10.5, weight: .semibold))
          }
          Text(target.appName)
            .font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
        }
      }
    }
    .foregroundStyle(model.hoveredSkill != nil ? Color.white : SilliesTheme.ink)
    .padding(.horizontal, 11).padding(.vertical, 5)
    .background(
      Capsule().fill(
        model.hoveredSkill != nil ? SilliesTheme.accent : SilliesTheme.card.opacity(0.97))
    )
    .overlay(
      Capsule().strokeBorder(
        model.hoveredSkill != nil ? Color.white.opacity(0.4) : SilliesTheme.border, lineWidth: 0.8)
    )
    .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
    .padding(12)
  }
}

/// Only the outline uses window-sized geometry; SwiftUI lays out a small, fixed-size badge.
@MainActor
private final class WindowDropOutlineView: NSView {
  private let outline = CAShapeLayer()
  private let badge: NSHostingView<WindowDropHighlightView>

  init(model: WindowDropHighlightModel) {
    badge = NSHostingView(rootView: WindowDropHighlightView(model: model))
    super.init(frame: SkillOverlayPreparation.target.frame)
    wantsLayer = true
    layer?.addSublayer(outline)
    addSubview(badge)
    outline.fillColor = nil
    outline.lineJoin = .round
    updateSelection(false)
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    outline.frame = bounds
    outline.path = CGPath(
      roundedRect: bounds.insetBy(dx: 3, dy: 3), cornerWidth: 12, cornerHeight: 12,
      transform: nil)
    CATransaction.commit()
    let width = min(400, bounds.width)
    badge.frame = CGRect(
      x: (bounds.width - width) / 2, y: bounds.height - 66, width: width, height: 56)
  }

  func updateSelection(_ selected: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.strokeColor =
      NSColor(
        srgbRed: 0.52, green: 0.47, blue: 0.77, alpha: selected ? 0.95 : 0.72
      ).cgColor
    outline.lineWidth = selected ? 3 : 2.2
    CATransaction.commit()
  }
}

/// Highlights the candidate target window underneath a dragged companion.
@MainActor
final class WindowDropHighlightController {
  private let model = WindowDropHighlightModel()
  private var panel: SkillFloatingPanel?
  private var outlineView: WindowDropOutlineView?
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }

  func prepare() {
    guard panel == nil else { return }
    model.target = SkillOverlayPreparation.target
    let created = SkillFloatingPanel(
      contentRect: SkillOverlayPreparation.target.frame, ignoresMouseEvents: true, level: .floating)
    let view = WindowDropOutlineView(model: model)
    created.contentView = view
    panel = created
    outlineView = view
    SkillOverlayPreparation.render(view)
  }

  func show(target: WindowTargetCandidate, hoveredSkill: CompanionSkillKind?) {
    prepare()
    ApplicationIconCache.shared.prepare(for: target)
    if model.target?.processID != target.processID || model.target?.appName != target.appName {
      model.target = target
    }
    if model.hoveredSkill != hoveredSkill {
      model.hoveredSkill = hoveredSkill
      outlineView?.updateSelection(hoveredSkill != nil)
    }
    let highlightFrame = target.frame.insetBy(dx: -2, dy: -2)
    if panel?.frame != highlightFrame {
      panel?.setFrame(highlightFrame, display: false)
    }
    if panel?.isVisible != true { panel?.orderFrontRegardless() }
  }

  func hide() {
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    outlineView = nil
  }
}

@MainActor @Observable
final class RadialWheelModel {
  var companionName = ""
  var target: WindowTargetCandidate?
  var layout = RadialSkillMenuLayout(
    center: .zero, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
  var hoveredSkill: CompanionSkillKind?
  var panelOrigin = CGPoint.zero
}

struct RadialWheelView: View {
  let model: RadialWheelModel

  private var centerInCanvas: CGPoint {
    CGPoint(
      x: model.layout.anchor.x - model.panelOrigin.x,
      y: RadialWheelController.canvasSize.height - (model.layout.anchor.y - model.panelOrigin.y))
  }

  var body: some View {
    let anchor = centerInCanvas
    let orbitDiameter = RadialSkillMenuLayout.orbitRadius * 2

    ZStack {
      // Subtle orbital guide ring connecting the 4 skill bubbles
      Circle()
        .strokeBorder(
          SilliesTheme.accent.opacity(0.28),
          style: StrokeStyle(lineWidth: 1.2, dash: [4, 5])
        )
        .frame(width: orbitDiameter, height: orbitDiameter)
        .position(anchor)

      // Soft anchor halo around the dragged companion
      Circle()
        .fill(SilliesTheme.accent.opacity(0.08))
        .frame(width: 54, height: 54)
        .overlay(
          Circle().strokeBorder(SilliesTheme.accent.opacity(0.35), lineWidth: 1.2)
        )
        .position(anchor)

      // Radial skill bubbles (no bottom text banner)
      ForEach(model.layout.items) { item in
        let isSelected = model.hoveredSkill == item.skill
        let localX = item.center.x - model.panelOrigin.x
        let localY = RadialWheelController.canvasSize.height - (item.center.y - model.panelOrigin.y)

        VStack(spacing: 5) {
          ZStack {
            Circle()
              .fill(isSelected ? SilliesTheme.accent : SilliesTheme.card.opacity(0.98))
              .frame(width: 48, height: 48)
              .shadow(
                color: isSelected
                  ? SilliesTheme.accent.opacity(0.42)
                  : Color.black.opacity(0.16),
                radius: isSelected ? 12 : 7, y: 3
              )
              .overlay(
                Circle().strokeBorder(
                  isSelected ? Color.white.opacity(0.9) : SilliesTheme.border,
                  lineWidth: isSelected ? 2 : 1))
            Image(systemName: item.skill.symbolName)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(isSelected ? Color.white : SilliesTheme.ink)
          }
          Text(item.skill.shortTitle)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(
              Capsule().fill(
                isSelected ? SilliesTheme.accent : SilliesTheme.card.opacity(0.97))
            )
            .overlay(
              Capsule().strokeBorder(
                isSelected ? Color.white.opacity(0.5) : SilliesTheme.border.opacity(0.8),
                lineWidth: 0.7)
            )
            .foregroundStyle(isSelected ? Color.white : SilliesTheme.ink)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .position(x: localX, y: localY)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isSelected)
      }
    }
    .frame(
      width: RadialWheelController.canvasSize.width,
      height: RadialWheelController.canvasSize.height)
  }
}

@MainActor
final class RadialWheelController {
  static let canvasSize = CGSize(width: 360, height: 320)

  private let model = RadialWheelModel()
  private var panel: SkillFloatingPanel?
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }

  func prepare() {
    guard panel == nil else { return }
    let created = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.canvasSize), ignoresMouseEvents: true)
    let view = NSHostingView(rootView: RadialWheelView(model: model))
    created.contentView = view
    panel = created
    SkillOverlayPreparation.render(view)
  }

  func show(
    companionName: String, target: WindowTargetCandidate, layout: RadialSkillMenuLayout,
    hoveredSkill: CompanionSkillKind?
  ) {
    prepare()
    let origin = CGPoint(
      x: layout.anchor.x - Self.canvasSize.width / 2,
      y: layout.anchor.y - Self.canvasSize.height / 2)
    if model.companionName != companionName { model.companionName = companionName }
    if model.target != target { model.target = target }
    if model.layout != layout { model.layout = layout }
    if model.hoveredSkill != hoveredSkill { model.hoveredSkill = hoveredSkill }
    if model.panelOrigin != origin { model.panelOrigin = origin }
    if panel?.frame.origin != origin { panel?.setFrameOrigin(origin) }
    if panel?.isVisible != true { panel?.orderFrontRegardless() }
  }

  func hide() {
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
  }
}

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
    let needsPermission = summary.localizedCaseInsensitiveContains("permission")
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
            let factor = index == 1 ? 1.0 : 0.65
            let barHeight = max(4.0, min(14.0, 4.0 + audioLevel * 11.0 * factor))
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

  private enum LayoutKey: Equatable {
    case hidden
    case selection(appName: String)
    case active(skill: CompanionSkillKind, appName: String, detailLength: Int)
    case completed(skill: CompanionSkillKind, appName: String, summary: String)

    init(_ state: CompanionBindingState) {
      switch state {
      case .followingFocusedWindow:
        self = .hidden
      case .awaitingSelection(let target, _):
        self = .selection(appName: target.appName)
      case .active(let target, let skill, _, let statusDetail, _):
        self = .active(
          skill: skill, appName: target.appName, detailLength: statusDetail.count)
      case .completed(let target, let skill, let summary, _, _):
        self = .completed(skill: skill, appName: target.appName, summary: summary)
      }
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
    if panel == nil {
      let host = NSHostingView(rootView: CompanionHUDView(model: model))
      let created = SkillFloatingPanel(
        contentRect: CGRect(origin: .zero, size: Self.fallbackSize), ignoresMouseEvents: false)
      created.contentView = host
      hostingView = host
      panel = created
      lastLayoutKey = nil
      cachedPanelSize = nil
    }
    let key = LayoutKey(state)
    let panelSize: CGSize
    if key == lastLayoutKey, let cachedPanelSize {
      panelSize = cachedPanelSize
    } else {
      layoutMeasurements += 1
      hostingView?.layoutSubtreeIfNeeded()
      let fitting = hostingView?.fittingSize ?? Self.fallbackSize
      let measured = CGSize(
        width: max(220, ceil(fitting.width)),
        height: max(52, ceil(fitting.height)))
      lastLayoutKey = key
      cachedPanelSize = measured
      panelSize = measured
    }

    let headTopOffset = characterSize * 0.78
    let unclampedX = companionPoint.x - panelSize.width / 2
    let clampedX = min(
      max(unclampedX, visibleFrame.minX + 6),
      visibleFrame.maxX - panelSize.width - 6)
    let preferredY = companionPoint.y + headTopOffset
    let clampedY = min(
      max(preferredY, visibleFrame.minY + 6),
      visibleFrame.maxY - panelSize.height - 2)

    let frame = CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
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
}
