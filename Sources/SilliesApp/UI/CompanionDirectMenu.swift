import AppKit
import SilliesCore
import SwiftUI

/// One transient menu owned by the shared interaction controller, never by a per-mascot timer.
@MainActor final class CompanionDirectMenu: NSObject, NSPopoverDelegate {
  private let appearance: ThemeEnvironment
  var onClose: (() -> Void)?
  private var popover: NSPopover?
  private weak var companion: CompanionInstance?
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
    super.init()
  }
  func show(for pet: CompanionInstance, perform: @escaping (CompanionMenuAction) -> Void) {
    close()
    pet.beginDirectActionMenu()
    companion = pet
    let popover = NSPopover()
    popover.delegate = self
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.contentViewController = ThemedHostingController(
      rootView: DirectActionsView { [weak self] action in
        self?.close()
        perform(action)
      }, appearance: appearance)
    self.popover = popover
    popover.show(relativeTo: pet.view.bounds, of: pet.view, preferredEdge: .minY)
  }
  func popoverDidClose(_ notification: Notification) {
    companion?.endDirectActionMenu()
    companion = nil
    onClose?()
  }
  func close() {
    popover?.close()
    popover = nil
    companion?.endDirectActionMenu()
    companion = nil
  }
}

private struct DirectActionsView: View {
  @Environment(\.silliesTheme) private var theme
  let perform: (CompanionMenuAction) -> Void
  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 28) {
        action(
          String(localized: "Chat"), symbol: "bubble.left.and.bubble.right.fill",
          command: .skill(.chat))
        action(String(localized: "Talk"), symbol: "waveform", command: .talk)
      }
      Divider()
      HStack(spacing: 18) {
        Button("Record", systemImage: "mic.fill") { perform(.skill(.record)) }
        Button("Pocket Stash", systemImage: "tray") { perform(.openStash) }
      }.font(.callout).buttonStyle(SoftButtonStyle())
    }.padding(20).background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
  }
  private func action(_ title: String, symbol: String, command: CompanionMenuAction) -> some View {
    Button {
      perform(command)
    } label: {
      VStack(spacing: 7) {
        Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
          .frame(width: 56, height: 56)
          .background(theme.accentFill, in: Circle()).foregroundStyle(theme.onAccent)
        Text(title).font(.system(.callout, design: .rounded).weight(.bold))
      }
    }.buttonStyle(.plain)
  }
}
