import AppKit
import SilliesDesign
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func crewSegmentsFillTheirColumnAtBothPanelAndSettingsWidths() throws {
  let fixture = try CrewControlsFixture()
  defer { fixture.close() }
  let energy = try fixture.control(labeled: "Energy")
  let position = try fixture.control(labeled: "Position")
  for width in [380.0, 540.0] {
    fixture.resize(width: width)
    let energyFrame = fixture.host.convert(energy.bounds, from: energy)
    let positionFrame = fixture.host.convert(position.bounds, from: position)
    let columnEnd = width - CrewControlsFixture.padding
    #expect(abs(energyFrame.minX - positionFrame.minX) < 1)
    #expect(abs(energyFrame.maxX - columnEnd) < 1)
    #expect(abs(positionFrame.maxX - columnEnd) < 1)
    #expect(abs(energyFrame.height - positionFrame.height) < 1)
    #expect(energyFrame.width > energy.intrinsicContentSize.width)
    #expect(try fixture.control(labeled: "Energy") === energy)
    #expect(energy.selectedSegment == 1)
    #expect(position.selectedSegment == 0)
  }
}

@Test @MainActor func nativeCrewSegmentsChangeAndPersistOnlyTheirBoundPreference() throws {
  let fixture = try CrewControlsFixture()
  defer { fixture.close() }
  let energy = try fixture.control(labeled: "Energy")
  let position = try fixture.control(labeled: "Position")
  energy.selectedSegment = 0
  #expect(energy.sendAction(energy.action, to: energy.target))
  #expect(fixture.settings.activity == .calm)
  #expect(fixture.settings.followsWindows)
  position.selectedSegment = 1
  #expect(position.sendAction(position.action, to: position.target))
  #expect(!fixture.settings.followsWindows)
  let reloaded = AppSettings(defaults: fixture.defaults)
  #expect(reloaded.activity == .calm)
  #expect(!reloaded.followsWindows)
  #expect(reloaded.size == AppSettings.defaultSize)

  // AppKit may report no selected segment; that is not a domain preference change.
  for index in 0..<energy.segmentCount { energy.setSelected(false, forSegment: index) }
  #expect(energy.sendAction(energy.action, to: energy.target))
  #expect(fixture.settings.activity == .calm)
}

@Test @MainActor func crewSegmentsRecolorInPlaceAcrossBundledThemesAndAppearances() async throws {
  let themes = try await Task.detached { try ThemeCatalog.loadBundled() }.value
  let fixture = try CrewControlsFixture()
  defer { fixture.close() }
  let controls = try [fixture.control(labeled: "Energy"), fixture.control(labeled: "Position")]
  let frames = controls.map(\.frame)
  for definition in themes {
    let theme = SilliesTheme(definition: definition)
    fixture.appearance.update(theme)
    for name in [NSAppearance.Name.aqua, .darkAqua] {
      let appearance = try #require(NSAppearance(named: name))
      fixture.setAppearance(appearance)
      for control in controls {
        var colorsMatch = false
        for _ in 0..<20 {
          try await Task.sleep(for: .milliseconds(10))
          fixture.host.layoutSubtreeIfNeeded()
          let bitmap = try #require(control.bitmapImageRepForCachingDisplay(in: control.bounds))
          control.cacheDisplay(in: control.bounds, to: bitmap)
          let sRGBBitmap = try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
          appearance.performAsCurrentDrawingAppearance {
            colorsMatch =
              selectedSegmentContains(theme.native(.accentFill), control, sRGBBitmap)
              && selectedSegmentContains(theme.native(.onAccent), control, sRGBBitmap)
          }
          if colorsMatch { break }
        }
        #expect(colorsMatch, "Selected fill and text must use \(definition.id) / \(name.rawValue)")
      }
      #expect(try fixture.control(labeled: "Energy") === controls[0])
      #expect(try fixture.control(labeled: "Position") === controls[1])
      #expect(controls.map(\.frame) == frames)
      #expect(controls.map(\.selectedSegment) == [1, 0])
    }
  }
}

@MainActor private func selectedSegmentContains(
  _ color: NSColor, _ control: NSSegmentedControl, _ sRGBBitmap: NSBitmapImageRep
) -> Bool {
  guard let expected = color.usingColorSpace(.sRGB), control.selectedSegment >= 0 else {
    return false
  }
  let width = sRGBBitmap.pixelsWide / control.segmentCount
  let start = control.selectedSegment * width
  let tolerance = 0.03
  // Sample inside the selection, where both its background and label must be visible.
  for x in (start + width / 4)..<(start + width * 3 / 4) {
    for y in sRGBBitmap.pixelsHigh / 4..<sRGBBitmap.pixelsHigh * 3 / 4 {
      // colorAt returns calibrated colors even for tagged bitmaps; compare converted components.
      guard let actual = sRGBBitmap.colorAt(x: x, y: y) else { continue }
      if abs(actual.redComponent - expected.redComponent) < tolerance,
        abs(actual.greenComponent - expected.greenComponent) < tolerance,
        abs(actual.blueComponent - expected.blueComponent) < tolerance
      {
        return true
      }
    }
  }
  return false
}

@MainActor private final class CrewControlsFixture {
  static let padding: CGFloat = 20
  private static let height: CGFloat = 170
  private let suite = "sillies-crew-controls-\(UUID())"
  let defaults: UserDefaults
  let settings: AppSettings
  let appearance = ThemeEnvironment()
  let host: NSHostingView<AnyView>
  private let window: NSWindow

  init() throws {
    defaults = try #require(UserDefaults(suiteName: suite))
    settings = AppSettings(defaults: defaults)
    host = NSHostingView(
      rootView: AnyView(
        ThemedContent(
          appearance: appearance,
          content: CompanionControls(settings: settings).padding(Self.padding))))
    host.sizingOptions = []
    window = NSWindow(
      contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    resize(width: 380)
  }

  func resize(width: CGFloat) {
    let size = CGSize(width: width, height: Self.height)
    window.setContentSize(size)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
  }

  func control(labeled label: String) throws -> NSSegmentedControl {
    try #require(controls(in: host).first { $0.accessibilityLabel() == label })
  }

  func setAppearance(_ appearance: NSAppearance) {
    window.appearance = appearance
  }

  func close() {
    window.close()
    defaults.removePersistentDomain(forName: suite)
  }

  private func controls(in view: NSView) -> [NSSegmentedControl] {
    if let control = view as? NSSegmentedControl { return [control] }
    return view.subviews.flatMap { controls(in: $0) }
  }
}
