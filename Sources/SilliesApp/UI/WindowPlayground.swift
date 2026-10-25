import AppKit
import QuartzCore
import SwiftUI

/// A real native window: the ordinary tracking pipeline follows it, including in runtime checks.
@MainActor
final class WindowPlayground: NSObject {
  let window: NSWindow
  private let controller: CompanionController
  private var squeezed = false
  private var moved = false
  private(set) var targetFrame = CGRect.zero
  private var animationLink: CADisplayLink?
  private var animationStart = CGRect.zero
  private var animationStartedAt: Double = 0

  init(controller: CompanionController) {
    self.controller = controller
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 860, height: 470),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    super.init()
    window.title = "Sillies · Window Playground"
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.minSize = CGSize(width: 520, height: 330)
    let host = NSHostingController(
      rootView: PlaygroundView(
        controller: controller,
        resize: { [weak self] in self?.squeeze() },
        move: { [weak self] in self?.nudge() },
        tall: { [weak self] in self?.makeTall() },
        reset: { [weak self] in self?.reset() }))
    // The user controls this resizable window; do not infer its minimum from an unconstrained SwiftUI proposal.
    host.sizingOptions = []
    window.contentViewController = host
    reset(animated: false)
  }

  func show() {
    controller.settings.followsWindows = true
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
      self?.controller.tracker.refreshFocus()
    }
  }

  private var fallbackVisibleFrame: CGRect {
    (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
  }

  func reset(animated: Bool = true) {
    let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? fallbackVisibleFrame
    let size = CGSize(width: min(860, visible.width - 260), height: min(470, visible.height - 250))
    let frame = CGRect(
      x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 - 35, width: size.width,
      height: size.height)
    squeezed = false
    moved = false
    if animated { animate(to: frame) } else { window.setFrame(frame, display: true) }
    targetFrame = frame
  }

  func squeeze() {
    squeezed.toggle()
    let width = squeezed ? 570.0 : 860.0
    var frame = window.frame
    frame.origin.x += (frame.width - width) / 2
    frame.size.width = width
    animate(to: frame)
  }

  func nudge() {
    moved.toggle()
    animate(to: window.frame.offsetBy(dx: moved ? 85 : -85, dy: moved ? 30 : -30))
  }

  func makeTall() {
    let visible = fallbackVisibleFrame
    var frame = window.frame
    frame.origin.y = visible.minY + 45
    frame.size.height = visible.height - 55
    animate(to: frame)
  }

  private func animate(to frame: CGRect) {
    animationLink?.invalidate()
    animationStart = window.frame
    animationStartedAt = ProcessInfo.processInfo.systemUptime
    targetFrame = frame
    let link = window.displayLink(target: self, selector: #selector(advanceAnimation(_:)))
    link.add(to: .main, forMode: .common)
    animationLink = link
  }

  @objc private func advanceAnimation(_ link: CADisplayLink) {
    let t = min((ProcessInfo.processInfo.systemUptime - animationStartedAt) / 0.65, 1)
    let eased = t * t * (3 - 2 * t)
    let start = animationStart
    let end = targetFrame
    window.setFrame(
      CGRect(
        x: start.minX + (end.minX - start.minX) * eased,
        y: start.minY + (end.minY - start.minY) * eased,
        width: start.width + (end.width - start.width) * eased,
        height: start.height + (end.height - start.height) * eased), display: true)
    if t >= 1 {
      link.invalidate()
      animationLink = nil
    }
  }
}

private struct PlaygroundView: View {
  let controller: CompanionController
  let resize: () -> Void
  let move: () -> Void
  let tall: () -> Void
  let reset: () -> Void
  @State private var tab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 7) {
        ForEach(
          Array(["A little space", "A little focus", "A little mischief"].enumerated()),
          id: \.offset
        ) { index, title in
          Button {
            tab = index
            controller.playReaction(.contextChanged)
          } label: {
            Text(title).font(.system(size: 11, weight: tab == index ? .semibold : .regular))
              .padding(.horizontal, 14).padding(.vertical, 9)
              .background(tab == index ? SilliesTheme.card : Color.clear, in: Capsule())
          }.buttonStyle(.plain)
        }
        Spacer()
        Image(systemName: "sparkles").foregroundStyle(SilliesTheme.accent)
      }.padding(8).background(SilliesTheme.soft, in: RoundedRectangle(cornerRadius: 14))
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 12) {
        Text(
          [
            "Small crew.\nBig window energy.", "You do your thing.\nThey’ll keep you company.",
            "Go on.\nShake things up a little.",
          ][tab]
        )
        .font(.system(size: 35, weight: .bold, design: .rounded)).tracking(-1.2)
        .fixedSize(horizontal: false, vertical: true)
        Text(
          "Drag this window. Grab a corner. Your crew should hang on,\nfind their footing, and make a tiny scene about it."
        )
        .font(.system(size: 12)).foregroundStyle(SilliesTheme.secondary).lineSpacing(4)
      }
      HStack(spacing: 9) {
        Button(
          "Squeeze", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
          action: resize)
        Button("Nudge", systemImage: "hand.draw", action: move)
        Button("Make it tall", systemImage: "arrow.up.and.down", action: tall)
        Spacer()
        Button("Start over", action: reset)
      }.font(.system(size: 11, weight: .medium)).buttonStyle(SoftButtonStyle())
      Spacer(minLength: 0)
      HStack {
        Circle().fill(Color(hex: "7DA78B")).frame(width: 6, height: 6)
        Text(controller.restingDescription).font(.system(size: 10)).foregroundStyle(
          SilliesTheme.secondary)
        Spacer()
        Text("This is their window. The rest is yours.").font(.system(size: 10)).foregroundStyle(
          SilliesTheme.secondary)
      }
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink)
  }
}
