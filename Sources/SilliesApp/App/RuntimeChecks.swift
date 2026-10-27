import AppKit
import Darwin
import SilliesCore

struct CompanionDiagnostics {
  let companionCount: Int
  let visibleCount: Int
  let visibleHUDCount: Int
  let movementClockRunning: Bool
  let decisionClockRunning: Bool
  let clickThrough: Bool
  let nonactivating: Bool
}

struct LaunchConfiguration {
  private static let inputCheckWatchdogTimeoutSeconds: Double = 60
  let arguments: [String]

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    self.arguments = arguments
  }

  var runsInputFixture: Bool { arguments.contains("--input-fixture") }
  var usesDarkAppearance: Bool { arguments.contains("--dark") }
  var usesAccessibility: Bool { !arguments.contains("--without-accessibility") }
  var validatesCatalogOnly: Bool { arguments.contains("--validate-catalog") }
  var showsPreview: Bool {
    arguments.contains("--preview") || arguments.contains("--snapshot-dir")
  }
  var isAutomatedRun: Bool {
    arguments.contains("--smoke-test") || arguments.contains("--snapshot-dir")
      || arguments.contains("--performance-check") || arguments.contains("--window-test")
      || arguments.contains("--external-drag-test")
      || arguments.contains("--drag-latency-test")
      || arguments.contains("--presentation-test")
      || arguments.contains("--interaction-test")
      || arguments.contains("--drop-return-test")
      || arguments.contains("--companion-drag-test")
  }

  var watchdogTimeoutSeconds: Double {
    if arguments.contains("--interaction-test") || arguments.contains("--drop-return-test") {
      return Self.inputCheckWatchdogTimeoutSeconds
    }
    return arguments.contains("--performance-check") ? 45 : 25
  }

  func optionValue(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  @MainActor
  func apply(to settings: AppSettings) {
    if isAutomatedRun { settings.followsWindows = false }
    if arguments.contains("--window-test") { settings.followsWindows = true }
    if arguments.contains("--drag-latency-test") { settings.followsWindows = true }
    if arguments.contains("--external-drag-test")
      || arguments.contains("--interaction-test")
    {
      settings.followsWindows = true
      settings.reduceMotion = true
    }
    if arguments.contains("--performance-check") {
      settings.followsWindows = true
      settings.activity = .calm
    }
    if arguments.contains("--drop-return-test") || arguments.contains("--companion-drag-test") {
      settings.followsWindows = true
      settings.reduceMotion = false
      settings.activity = .calm
    }
  }
}

/// Owns automated CLI/GUI check fixtures, watchdog timers, and command-line dispatch so
/// `AppDelegate` stays focused on application lifecycle and user-facing windows.
@MainActor
final class AutomatedLaunchRunner {
  private var inputFixture: InputWindowFixture?
  private var externalDragCheck: ExternalDragCheck?
  private var playInteractionCheck: PlayInteractionCheck?
  private var companionDragCheck: CompanionDragResponseCheck?
  private var watchdogTimer: DispatchSourceTimer?

  func armWatchdogIfNeeded(for launch: LaunchConfiguration) {
    guard launch.isAutomatedRun || launch.validatesCatalogOnly || launch.runsInputFixture else {
      return
    }
    let timeoutSeconds = launch.watchdogTimeoutSeconds
    let timer = DispatchSource.makeTimerSource(
      queue: DispatchQueue(label: "app.sillies.watchdog", qos: .userInteractive))
    timer.schedule(deadline: .now() + timeoutSeconds)
    timer.setEventHandler { @Sendable in
      FileHandle.standardError.write(
        Data("AUTOMATED CHECK WATCHDOG TIMEOUT after \(timeoutSeconds)s\n".utf8))
      _exit(1)
    }
    timer.resume()
    watchdogTimer = timer
  }

  func startInputFixture() {
    let fixture = InputWindowFixture()
    inputFixture = fixture
    fixture.start()
  }

  func run(
    _ launch: LaunchConfiguration,
    controller: CompanionController,
    openPlayground: () -> WindowPlayground,
    exportPreviews: @escaping (URL) -> Void
  ) {
    let args = launch.arguments
    if let snapshotPath = launch.optionValue(after: "--snapshot-dir") {
      let directory = URL(fileURLWithPath: snapshotPath, isDirectory: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        exportPreviews(directory)
        NSApp.terminate(nil)
      }
    } else if args.contains("--smoke-test") {
      RuntimeChecks.smokeTest(controller)
    } else if args.contains("--presentation-test") {
      RuntimeChecks.presentationTest()
    } else if args.contains("--interaction-test") || args.contains("--drop-return-test") {
      let previous = NSWorkspace.shared.frontmostApplication
      let playground = openPlayground()
      playInteractionCheck = PlayInteractionCheck(
        controller: controller,
        playground: playground,
        previousApplication: previous,
        mode: args.contains("--drop-return-test") ? .dropReturn : .interaction)
      playInteractionCheck?.start()
    } else if args.contains("--companion-drag-test") {
      guard let target = launch.optionValue(after: "--target-bundle") else {
        fputs("--companion-drag-test requires --target-bundle\n", stderr)
        NSApp.terminate(nil)
        return
      }
      companionDragCheck = CompanionDragResponseCheck(controller: controller, targetBundle: target)
      companionDragCheck?.start()
    } else if args.contains("--performance-check") {
      _ = openPlayground()
      RuntimeChecks.performanceCheck(controller)
    } else if args.contains("--window-test") {
      let playground = openPlayground()
      RuntimeChecks.windowTest(controller, playground: playground)
    } else if args.contains("--drag-latency-test") {
      let playground = openPlayground()
      DragLatencyCheck(
        controller: controller,
        playground: playground,
        allowLag: args.contains("--allow-lag")
      ).start()
    } else if args.contains("--external-drag-test") {
      let targetBundle = launch.optionValue(after: "--target-bundle")
      let fraction = launch.optionValue(after: "--target-header-fraction").flatMap(Double.init)
      externalDragCheck = ExternalDragCheck(
        controller: controller,
        targetBundle: targetBundle,
        targetHeaderFraction: fraction,
        expectsStationary: args.contains("--expect-stationary"))
      externalDragCheck?.start()
    } else if args.contains("--playground") {
      _ = openPlayground()
    }
  }
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
      interaction.refresh(at: transparentPoint)
      require(
        panel.ignoresMouseEvents,
        "Transparent panel regions pass clicks through to background windows")
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
    let crew = Set(controller.catalog.characters.map(\.id))
    require(controller.diagnostics.companionCount == crew.count, "All companions load")
    require(controller.diagnostics.visibleCount == crew.count, "Companion panels are visible")
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
      require(controller.diagnostics.visibleCount == crew.count, "Resume restores panels")
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
            at: CGPoint(x: attachment.point.x + 28, y: attachment.point.y + 20)) == 0
            && controller.blockingCompanionCount(
              at: CGPoint(x: attachment.point.x + 70, y: attachment.point.y)) == 0,
          "Transparent panel canvas always passes input through")
      }
      controller.settings.enabledCharacters.remove("mochi")
      require(
        controller.diagnostics.companionCount == crew.count - 1,
        "Disabling a character releases its panel")
      controller.settings.enabledCharacters.insert("mochi")
      require(
        controller.diagnostics.companionCount == crew.count,
        "Re-enabling a character restores its panel")
      controller.settings.enabledCharacters.removeAll()
      require(!controller.diagnostics.decisionClockRunning, "An empty crew has no decision timer")
      controller.settings.enabledCharacters = crew
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
        report("\(controller.liveCount)-companion-window-following-calm", since: start)
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
