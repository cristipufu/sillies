import AppKit
import SilliesCore
import SwiftUI

/// One shared, nonactivating action wheel; closing releases the mascot and event monitors.
@MainActor final class CompanionDirectMenu {
  private static let shadowPadding: CGFloat = 16
  private static let entranceDuration: TimeInterval = 0.16
  private let appearance: ThemeEnvironment
  private let interaction = RadialMenuInteraction()
  private var panel: SkillFloatingPanel?
  private weak var companion: CompanionInstance?
  var windowNumber: Int? { panel?.windowNumber }
  var onClose: (() -> Void)?
  init(appearance: ThemeEnvironment) { self.appearance = appearance }

  func show(for pet: CompanionInstance, perform: @escaping (CompanionMenuAction) -> Void) {
    close()
    pet.beginDirectActionMenu()
    companion = pet
    let widths = CompanionDirectAction.allCases.map(\.titleWidth)
    let layout = makeLayout(for: pet, titleWidths: widths)
    let panel = makePanel(for: pet, layout: layout, perform: perform)
    self.panel = panel
    interaction.start(
      panel: panel,
      localRegions: zip(layout.centers, widths).map {
        RadialMenuItemLayout(
          center: CGPoint(x: $0.x - layout.frame.minX, y: $0.y - layout.frame.minY), titleWidth: $1)
      }
    ) { [weak self] in self?.close() }
    reveal(panel, above: pet.panel.windowNumber)
  }

  private func makeLayout(for pet: CompanionInstance, titleWidths widths: [CGFloat])
    -> CompanionActionMenuLayout
  {
    let size = CGSize(
      width: max(RadialMenuItemLayout.iconDiameter, widths.max() ?? 0),
      height: RadialMenuItemLayout.height)
    return CompanionActionMenuLayout(
      anchor: CGPoint(x: pet.panel.frame.midX, y: pet.panel.frame.midY), count: widths.count,
      itemSize: CGSize(
        width: size.width * RadialMenuItemLayout.selectedScale + Self.shadowPadding,
        height: size.height * RadialMenuItemLayout.selectedScale + Self.shadowPadding),
      visibleFrame: CompanionPanel.visibleFrame(for: pet.panel.screen))
  }

  private func makePanel(
    for pet: CompanionInstance, layout: CompanionActionMenuLayout,
    perform: @escaping (CompanionMenuAction) -> Void
  ) -> SkillFloatingPanel {
    let panel = SkillFloatingPanel(
      contentRect: layout.frame, ignoresMouseEvents: true,
      level: CompanionPanel.hudLevel(forWindowLayer: pet.attachedWindowLayer), focus: .keyboard)
    let host = ThemedHostingView(
      rootView: CompanionDirectMenuView(layout: layout) { [weak self] action in
        self?.close()
        perform(action.command)
      }, appearance: appearance)
    host.sizingOptions = []
    panel.contentView = host
    return panel
  }

  private func reveal(_ panel: SkillFloatingPanel, above companionWindow: Int) {
    let targetAlpha = panel.alphaValue
    panel.alphaValue = 0
    panel.order(.above, relativeTo: companionWindow)
    panel.makeKey()
    NSAnimationContext.runAnimationGroup { context in
      context.duration =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.entranceDuration
      panel.animator().alphaValue = targetAlpha
    }
  }
  func close() {
    let wasOpen = panel != nil
    interaction.stop()
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    companion?.endDirectActionMenu()
    companion = nil
    if wasOpen { onClose?() }
  }
  func close(for pet: CompanionInstance) {
    if companion === pet { close() }
  }
  isolated deinit { close() }
}
