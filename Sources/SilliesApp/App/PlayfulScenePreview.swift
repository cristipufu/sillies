import AppKit
import Darwin
import SilliesCore

/// A bounded, isolated developer preview uses the same scene path as normal playback.
@MainActor
final class PlayfulScenePreview {
  private enum Failure: Error {
    case unavailable(String)
    case incomplete(String)
  }
  private static let setupDelay: Double = 0.4
  private static let completionAllowance: Double = 1
  private let controller: CompanionController
  private let window: NSWindow
  private var task: Task<Void, Never>?

  init(controller: CompanionController) {
    self.controller = controller
    let visible = CompanionPanel.visibleFrame()
    let frame = CGRect(
      x: visible.minX + 140, y: visible.minY + 70,
      width: min(700, visible.width - 380), height: max(260, visible.height - 410))
    window = NSWindow(
      contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Sillies · Playful scene preview"
    let label = NSTextField(
      wrappingLabelWithString:
        "A little room for mischief.\nThis preview uses temporary preferences and closes when the scene finishes."
    )
    label.frame = CGRect(x: 32, y: 40, width: frame.width - 64, height: 60)
    label.font = .systemFont(ofSize: 16)
    label.textColor = .secondaryLabelColor
    window.contentView?.addSubview(label)
  }

  func start(sceneID: String) {
    window.title = "Sillies · \(sceneID)"
    controller.settings.enabledCharacters = ["mochi", "kiko"]
    controller.settings.activity = .playful
    controller.settings.followsWindows = true
    controller.settings.reduceMotion = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    task = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(Self.setupDelay))
        guard let self else { return }
        self.controller.tracker.simulateTrackedWindow(
          self.window.frame, windowID: UInt32(self.window.windowNumber))
        self.controller.tracker.stop()
        let completedBefore = self.controller.playfulScenes.completedSceneCount
        guard self.controller.previewPlayfulScene(sceneID) else {
          throw Failure.unavailable(sceneID)
        }
        let duration = try PlayfulSceneCatalog().scenes.first { $0.id == sceneID }?.duration ?? 0
        print("Playing \(sceneID) for \(duration) seconds")
        try await Task.sleep(for: .seconds(duration + Self.completionAllowance))
        guard self.controller.playfulScenes.completedSceneCount == completedBefore + 1,
          !self.controller.playfulScenes.isActive, !self.controller.playfulScenes.hasVisibleProp
        else { throw Failure.incomplete(sceneID) }
        print("SCENE GUI OK: \(sceneID), completed and cleaned up")
        NSApp.terminate(nil)
      } catch is CancellationError {
      } catch {
        FileHandle.standardError.write(
          Data("Scene preview failed: \(error)\n".utf8))
        exit(EXIT_FAILURE)
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    window.close()
  }
}
