import AppKit
import Darwin
import SilliesCore

struct CompanionDiagnostics {
  let companionCount: Int
  let visibleCount: Int
  let movementClockRunning: Bool
  let decisionClockRunning: Bool
  let clickThrough: Bool
  let nonactivating: Bool
}

/// Explicit command-line checks; never enabled in an ordinary app session.
@MainActor
enum RuntimeChecks {
  static func presentationTest() {
    let view = CompanionView(rig: CatRig(), size: 64)
    let panel = CompanionPanel(view: view)
    panel.setFrameOrigin(CGPoint(x: 100, y: 200))
    let presentation = CompanionPresentation(
      panel: panel, view: view, profile: CharacterTransitions(), library: TransitionLibrary())
    presentation.show(reducedMotion: false)
    AnimationLibrary().apply(
      BehaviorState(animation: .walk), to: view.rig, characterID: "mochi", reducedMotion: false)
    require(
      view.presentationLayer.animation(forKey: "presentation") != nil,
      "Behavior changes preserve entry transitions")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
      presentation.hide()
      require(panel.ignoresMouseEvents, "An exiting companion passes input through")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      presentation.show(reducedMotion: true)
      require(panel.isVisible, "A new attachment interrupts exit immediately")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
      require(panel.isVisible, "A stale exit completion cannot hide a returned companion")
      verifyWindowInputPriority(panel: panel, view: view) { presentation.hide() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
      require(!panel.isVisible, "Finite exit completes and hides the panel")
      require(view.rig.leftFoot.animationKeys() == nil, "Hidden rigs stop behavior animations")
      presentation.show(reducedMotion: true)
      require(
        view.presentationLayer.animation(forKey: "presentation") == nil,
        "Reduce Motion presents a static character")
      presentation.close()
      print(
        "PRESENTATION OK: independent entry/exit, interrupted exit, stale completion, reduced motion, cleanup"
      )
      NSApp.terminate(nil)
    }
  }

  private static func verifyWindowInputPriority(
    panel: CompanionPanel, view: CompanionView, completion: @escaping @MainActor () -> Void
  ) {
    let point = CGPoint(x: panel.frame.midX, y: panel.frame.midY + 35)
    let transparentPoint = CGPoint(x: panel.frame.minX + 6, y: panel.frame.maxY - 6)
    let underlay = NSWindow(
      contentRect: CGRect(x: point.x - 100, y: point.y - 110, width: 250, height: 100),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    underlay.isReleasedWhenClosed = false
    underlay.level = panel.level
    underlay.orderFrontRegardless()
    underlay.order(.below, relativeTo: panel.windowNumber)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      let interaction = CompanionInteraction()
      let targets = [CompanionInteraction.Target(panel: panel, view: view, isDragging: { false })]
      interaction.configure(enabled: true, targets: targets)
      interaction.refresh(at: point)
      require(
        !panel.ignoresMouseEvents && view.containsInteractiveArtwork(at: point),
        "Play mode keeps character artwork interactive over background windows"
      )
      require(
        !view.containsInteractiveArtwork(at: transparentPoint),
        "Transparent panel regions are not interactive artwork")
      view.configureSurface(pose: .standing, window: underlay.frame, display: nil)
      interaction.refresh(at: point)
      require(
        panel.ignoresMouseEvents,
        "Focused window geometry remains protected"
      )
      require(
        NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == underlay.windowNumber,
        "WindowServer routes the click to the focused window")
      view.configureSurface(pose: .standing, window: nil, display: nil)
      interaction.stop()
      underlay.close()
      completion()
    }
  }

  static func windowTest(_ controller: CompanionController, playground: WindowPlayground) {
    WindowIntegrationCheck(controller: controller, playground: playground).start()
  }

  static func smokeTest(_ controller: CompanionController) {
    require(controller.diagnostics.companionCount == 2, "Both companions load")
    require(controller.diagnostics.visibleCount == 2, "Companion panels are visible")
    require(controller.diagnostics.nonactivating, "Panels cannot steal keyboard focus")
    controller.greet()
    if !controller.reducedMotion {
      require(controller.diagnostics.movementClockRunning, "Greeting begins movement")
      controller.settings.activity = .playful
      require(
        controller.diagnostics.movementClockRunning,
        "An unrelated preference preserves an in-flight movement")
      controller.settings.activity = .calm
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      controller.settings.paused = true
      let state = controller.diagnostics
      require(state.visibleCount == 0, "Pause hides panels")
      require(state.clickThrough, "Paused panels pass clicks through")
      require(!state.movementClockRunning && !state.decisionClockRunning, "Pause stops both clocks")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      controller.settings.paused = false
      require(controller.diagnostics.visibleCount == 2, "Resume restores panels")
      controller.settings.reduceMotion = true
      controller.greet()
      require(!controller.diagnostics.movementClockRunning, "Reduce Motion prevents movement")
      if let attachment = controller.attachmentDiagnostics.first {
        require(
          controller.interactiveArtworkCount(
            at: CGPoint(x: attachment.point.x, y: attachment.point.y + 35)) == 1,
          "Play mode detects visible character artwork")
        require(
          controller.blockingCompanionCount(
            at: CGPoint(x: attachment.point.x + 70, y: attachment.point.y)) == 0,
          "Transparent panel canvas always passes input through")
      }
      controller.settings.enabledCharacters.remove("mochi")
      require(
        controller.diagnostics.companionCount == 1, "Disabling a character releases its panel")
      controller.settings.enabledCharacters.insert("mochi")
      require(
        controller.diagnostics.companionCount == 2, "Re-enabling a character restores its panel")
      controller.settings.enabledCharacters.removeAll()
      require(!controller.diagnostics.decisionClockRunning, "An empty crew has no decision timer")
      controller.settings.enabledCharacters = ["mochi", "kiko"]
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      print(
        "SMOKE OK: characters, visibility, focus, pause/resume, reduced motion, interaction, removal, and empty-crew scheduling"
      )
      NSApp.terminate(nil)
    }
  }

  static func performanceCheck(_ controller: CompanionController) {
    // A small reproducible process-only measurement. Compositor/battery work needs Instruments.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      let start = sample()
      DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        report("two-companion-window-following-calm", since: start)
        controller.settings.paused = true
        let paused = sample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
          report("paused", since: paused)
          require(
            !controller.diagnostics.movementClockRunning
              && !controller.diagnostics.decisionClockRunning,
            "No animation clocks remain while paused")
          NSApp.terminate(nil)
        }
      }
    }
  }

  private struct Sample {
    let time: Double
    let cpu: Double
  }

  private static func sample() -> Sample {
    Sample(
      time: ProcessInfo.processInfo.systemUptime, cpu: Double(clock()) / Double(CLOCKS_PER_SEC))
  }

  private static func report(_ scenario: String, since start: Sample) {
    let end = sample()
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let cpu = 100 * (end.cpu - start.cpu) / (end.time - start.time)
    print(
      String(
        format: "PERF %@: %.3f%% average process CPU over %.1fs; peak RSS %.1f MiB", scenario, cpu,
        end.time - start.time, Double(usage.ru_maxrss) / 1_048_576))
    fflush(stdout)
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
      FileHandle.standardError.write(Data("RUNTIME CHECK FAILED: \(message)\n".utf8))
      exit(1)
    }
  }
}
