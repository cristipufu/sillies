import AppKit
import QuartzCore
import SilliesCore

/// The top part has its own tiny panel, so the corner never creates a rectangular input area over the document.
@MainActor
final class PlayfulRopeAnchorPresentation {
  private let panel = PlayfulPropPanel()
  private let view = PlayfulRopeAnchorView()
  private var lastFrame: CGRect?
  var isVisible: Bool { panel.isVisible }
  var preview: (NSView, CGRect)? { panel.preview }
  var windowNumbers: Set<Int> { panel.isVisible ? [panel.windowNumber] : [] }

  init() {
    view.wantsLayer = true
    panel.contentView = view
  }

  func place(actor: PlayfulSceneSession.Frame, plan: PlayfulScenePlan, level: NSWindow.Level) {
    guard let window = plan.window,
      let frame = PlayfulPropLayout.ropeTopFrame(actor: actor, plan: plan)
    else {
      hide()
      return
    }
    if lastFrame != frame {
      lastFrame = frame
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      view.setFrameSize(frame.size)
      view.update(path: PlayfulPropLayout.rope(in: frame, actor: actor, window: window).cornerPath)
      CATransaction.commit()
    }
    panel.present(frame: frame, level: level)
  }

  func hide() { panel.hide() }
  func close() {
    panel.close()
    lastFrame = nil
  }
}
