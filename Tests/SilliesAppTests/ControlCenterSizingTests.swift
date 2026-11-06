import AppKit
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func pawPanelHasItsFinalSizeBeforePopoverPresentation() throws {
  let suite = "app.sillies.test.popover.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer { removeTestFile(at: directory) }
  let controller = try CompanionController(
    settings: AppSettings(defaults: defaults),
    services: .init(
      accessibility: .disabled,
      skills: SkillCoordinator(vault: SessionVaultStore(directory: directory))))
  // Merely opening the stepped size control must preserve a saved, non-preset size.
  let savedSize = 70.0
  controller.settings.size = savedSize
  let content = ControlCenterView(
    controller: controller, actions: .init(openSettings: {}, openVault: {}, quit: {}))
  let host = ControlCenterHostingController(
    content: content, visibleFrame: CGRect(x: 0, y: 81, width: 1512, height: 868),
    appearance: ThemeEnvironment())
  #expect(host.sizingOptions.isEmpty)
  #expect(host.view.frame.size == CGSize(width: 420, height: 640))
  #expect(host.preferredContentSize == host.viewportSize)
  let popover = NSPopover()
  popover.contentViewController = host
  popover.contentSize = host.viewportSize
  host.view.layoutSubtreeIfNeeded()
  #expect(popover.contentSize == host.viewportSize)
  #expect(host.view.fittingSize == host.viewportSize)
  let previousAppearance = NSApp.appearance
  defer { NSApp.appearance = previousAppearance }
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSApp.appearance = NSAppearance(named: appearance)
    try renderSkillInterface(
      host.rootView, size: host.viewportSize,
      name: "sillies-launcher-\(appearance.rawValue)")
  }
  // Reopening on a shorter display updates the same host before AppKit chooses its position.
  host.updateViewport(visibleFrame: CGRect(x: 1512, y: 0, width: 1024, height: 500))
  popover.contentSize = host.viewportSize
  #expect(host.viewportSize == CGSize(width: 420, height: 476))
  #expect(host.view.frame.size == host.viewportSize)
  #expect(host.preferredContentSize == host.viewportSize)
  #expect(host.view.fittingSize == host.viewportSize)
  try renderSkillInterface(
    host.rootView, size: host.viewportSize, name: "sillies-launcher-short-display")
  #expect(controller.settings.size == savedSize)
  #expect(AppSettings(defaults: defaults).size == savedSize)
}
