import AppKit
import Observation

/// One presentation tree owns one palette. No process-global preference lookup is needed.
@MainActor @Observable final class ThemeEnvironment {
  private(set) var palette: SilliesTheme
  @ObservationIgnored private let windows = AppWindowAppearance()
  @ObservationIgnored private var observers: [Observer] = []
  private struct Observer {
    weak var owner: AnyObject?
    let apply: (SilliesTheme) -> Void
  }

  init(palette: SilliesTheme = SilliesTheme()) { self.palette = palette }

  func update(_ palette: SilliesTheme) {
    if self.palette != palette { self.palette = palette }
    windows.refresh(palette)
    observers.removeAll { $0.owner == nil }
    for observer in observers { observer.apply(palette) }
  }

  func register(_ window: NSWindow) { windows.register(window, theme: palette) }

  func observe<Owner: AnyObject>(_ owner: Owner, apply: @escaping (Owner, SilliesTheme) -> Void) {
    observers.removeAll { $0.owner == nil || $0.owner === owner }
    observers.append(
      .init(
        owner: owner,
        apply: { [weak owner] palette in
          if let owner { apply(owner, palette) }
        }))
    apply(owner, palette)
  }
}
