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
  let content = ControlCenterView(
    controller: controller, openSettings: {}, openPlayground: {}, quit: {})
  let host = ControlCenterHostingController(
    content: content, visibleFrame: CGRect(x: 0, y: 81, width: 1512, height: 868))
  #expect(host.sizingOptions.isEmpty)
  #expect(host.view.frame.size == CGSize(width: 388, height: 640))
  #expect(host.preferredContentSize == host.viewportSize)
  let popover = NSPopover()
  popover.contentViewController = host
  popover.contentSize = host.viewportSize
  host.view.layoutSubtreeIfNeeded()
  #expect(popover.contentSize == host.viewportSize)
  #expect(host.view.fittingSize == host.viewportSize)
  // Reopening on a shorter display updates the same host before AppKit chooses its position.
  host.updateViewport(visibleFrame: CGRect(x: 1512, y: 0, width: 1024, height: 500))
  popover.contentSize = host.viewportSize
  #expect(host.viewportSize == CGSize(width: 388, height: 476))
  #expect(host.view.frame.size == host.viewportSize)
  #expect(host.preferredContentSize == host.viewportSize)
  #expect(host.view.fittingSize == host.viewportSize)
}
