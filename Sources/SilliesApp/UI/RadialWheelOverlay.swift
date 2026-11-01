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
  private static let upwardItems = RadialSkillMenuLayout.items(
    around: canvasCenter, direction: .upward)
  private static let downwardItems = RadialSkillMenuLayout.items(
    around: canvasCenter, direction: .downward)

  let model: RadialWheelModel

  var body: some View {
    let anchor = Self.canvasCenter
    let items = model.flippedDownward ? Self.downwardItems : Self.upwardItems

    ZStack {
      RadialMenuOrbit(radius: RadialSkillMenuLayout.orbitRadius)
        .position(anchor)

      // Radial skill bubbles (no bottom text banner)
      ForEach(items) { item in
        let isSelected = model.hoveredSkill == item.skill
        let localX = item.center.x
        let localY = RadialWheelController.canvasSize.height - item.center.y

        RadialActionBubble(
          title: item.skill.shortTitle, symbol: item.skill.symbolName,
          isSelected: isSelected
        )
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
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

  static let canvasSize = CGSize(width: 440, height: 400)

  private let model = RadialWheelModel()
  private var panel: SkillFloatingPanel?
  private var appliedOrigin: CGPoint?
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }

  func prepare() {
    guard panel == nil else { return }
    let created = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.canvasSize), ignoresMouseEvents: true)
    let view = ThemedHostingView(rootView: RadialWheelView(model: model), appearance: appearance)
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
