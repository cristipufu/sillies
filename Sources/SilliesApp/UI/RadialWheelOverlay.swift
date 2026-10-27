import AppKit
import SilliesCore
import SwiftUI

@MainActor @Observable
final class RadialWheelModel {
  var flippedDownward = false
  var hoveredSkill: CompanionSkillKind?
}

struct RadialWheelView: View {
  private static let canvasCenter = CGPoint(
    x: RadialWheelController.canvasSize.width / 2,
    y: RadialWheelController.canvasSize.height / 2)
  private static let upwardLayout = RadialSkillMenuLayout(
    center: canvasCenter,
    visibleFrame: CGRect(x: 0, y: 0, width: 360, height: 480))
  private static let downwardLayout = RadialSkillMenuLayout(
    center: canvasCenter,
    visibleFrame: CGRect(x: 0, y: 0, width: 360, height: 220))
  private static let selectedBubbleScale: CGFloat = 1.12
  private static let unselectedBubbleScale: CGFloat = 1.0

  let model: RadialWheelModel

  var body: some View {
    let anchor = Self.canvasCenter
    let layout = model.flippedDownward ? Self.downwardLayout : Self.upwardLayout
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
      ForEach(layout.items) { item in
        let isSelected = model.hoveredSkill == item.skill
        let localX = item.center.x
        let localY = RadialWheelController.canvasSize.height - item.center.y

        VStack(spacing: 5) {
          ZStack {
            Circle()
              .fill(isSelected ? SilliesTheme.accent : SilliesTheme.card.opacity(0.98))
              .frame(width: 48, height: 48)
              .shadow(
                color: isSelected
                  ? SilliesTheme.accent.opacity(0.42)
                  : Color.black.opacity(0.16),
                radius: 6, y: 2
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
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
        .scaleEffect(isSelected ? Self.selectedBubbleScale : Self.unselectedBubbleScale)
        .position(x: localX, y: localY)
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
  private var appliedOrigin: CGPoint?
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }

  func prepare() {
    guard panel == nil else { return }
    let created = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.canvasSize), ignoresMouseEvents: true)
    let view = NSHostingView(rootView: RadialWheelView(model: model))
    view.sizingOptions = []
    created.contentView = view
    panel = created
    appliedOrigin = .zero
    SkillOverlayPreparation.render(view)
  }

  func show(layout: RadialSkillMenuLayout, hoveredSkill: CompanionSkillKind?) {
    prepare()
    let origin = CGPoint(
      x: (layout.anchor.x - Self.canvasSize.width / 2).rounded(),
      y: (layout.anchor.y - Self.canvasSize.height / 2).rounded())
    let flippedDownward = (layout.items.first?.center.y ?? layout.anchor.y) < layout.anchor.y
    if model.flippedDownward != flippedDownward { model.flippedDownward = flippedDownward }
    if model.hoveredSkill != hoveredSkill { model.hoveredSkill = hoveredSkill }
    if appliedOrigin != origin {
      appliedOrigin = origin
      panel?.setFrameOrigin(origin)
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
    appliedOrigin = nil
  }
}
