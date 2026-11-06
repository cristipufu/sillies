import AppKit
import SilliesDesign
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func increasedContrastUsesNativeWindowAndSelectionColors() throws {
  for name in [NSAppearance.Name.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
  {
    let appearance = try #require(NSAppearance(named: name))
    for (role, expectedColor) in [
      (ThemeColorRole.paper, NSColor.windowBackgroundColor),
      (.selection, NSColor.selectedTextBackgroundColor), (.onSelection, NSColor.selectedTextColor),
    ] {
      var actual: NSColor?
      var expected: NSColor?
      appearance.performAsCurrentDrawingAppearance {
        actual = SilliesTheme(contrast: .increased).native(role).usingColorSpace(.sRGB)
        expected = expectedColor.usingColorSpace(.sRGB)
      }
      #expect(try #require(actual) == #require(expected))
    }
  }
}

@Test @MainActor func themesKeepNativeTextSelectionAndTranscriptReadingPosition() async throws {
  let suite = "sillies-theme-test-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let preferences = AppearancePreferences(defaults: defaults)
  let environment = ThemeEnvironment()
  preferences.onChange = { [weak preferences] in
    environment.update(SilliesTheme(definition: preferences?.selectedTheme))
  }
  environment.update(SilliesTheme(definition: preferences.selectedTheme))
  defer {
    defaults.removePersistentDomain(forName: suite)
  }
  await preferences.load()
  let viewport = TranscriptScrollView()
  viewport.frame = CGRect(x: 0, y: 0, width: 350, height: 240)
  let words = (0..<500).map { "Line \($0): words that must remain selectable." }.joined(
    separator: "\n")
  viewport.update(text: words, followMode: .reading)
  viewport.textView.setSelectedRange(NSRange(location: 30, length: 40))
  viewport.contentView.scroll(to: CGPoint(x: 0, y: 80))
  let origin = viewport.contentView.bounds.origin
  for theme in preferences.themes {
    preferences.themeID = theme.id
    viewport.applyTheme(environment.palette)
    viewport.update(text: words, followMode: .reading)
    #expect(viewport.textView.string == words)
    #expect(viewport.textView.selectedRange() == NSRange(location: 30, length: 40))
    #expect(viewport.contentView.bounds.origin == origin)
    #expect(defaults.string(forKey: "colorTheme") == theme.id)
  }
  viewport.stopObserving()
}

@Test @MainActor func hostedTranscriptRecolorsWithoutReplacingOrRescrollingText() async throws {
  let suite = "sillies-theme-hosted-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let preferences = AppearancePreferences(defaults: defaults)
  await preferences.load()
  let environment = ThemeEnvironment()
  preferences.onChange = { [weak preferences] in
    environment.update(SilliesTheme(definition: preferences?.selectedTheme))
  }
  environment.update(SilliesTheme(definition: preferences.selectedTheme))
  let text = String(repeating: "A saved transcript remains readable.\n", count: 100)
  let host = ThemedHostingView(
    rootView: LiveTranscriptTextView(text: text, followsLive: .constant(false)),
    appearance: environment)
  let window = NSWindow(
    contentRect: CGRect(x: 80, y: 80, width: 380, height: 260), styleMask: [.titled],
    backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  defer {
    window.close()
    defaults.removePersistentDomain(forName: suite)
  }
  host.layoutSubtreeIfNeeded()
  let viewport = try #require(findTranscriptScrollView(in: host))
  viewport.textView.setSelectedRange(NSRange(location: 10, length: 12))
  viewport.contentView.scroll(to: CGPoint(x: 0, y: 80))
  let origin = viewport.contentView.bounds.origin
  preferences.themeID = "dracula"
  for _ in 0..<20 {
    try await Task.sleep(for: .milliseconds(10))
    host.layoutSubtreeIfNeeded()
    if viewport.textView.textColor?.usingColorSpace(.sRGB)
      == environment.palette.native(.ink).usingColorSpace(.sRGB)
    {
      break
    }
  }
  #expect(
    viewport.textView.textColor?.usingColorSpace(.sRGB)
      == environment.palette.native(.ink).usingColorSpace(.sRGB))
  #expect(viewport.textView.string == text)
  #expect(viewport.textView.selectedRange() == NSRange(location: 10, length: 12))
  #expect(viewport.contentView.bounds.origin == origin)
}

@Test @MainActor func everyBundledThemeFitsChatAndAppearanceSettingsInBothModes() async throws {
  let suite = "sillies-theme-interface-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let preferences = AppearancePreferences(defaults: defaults)
  let originalAppearance = NSApp.appearance
  let environment = ThemeEnvironment()
  preferences.onChange = { [weak preferences] in
    environment.update(SilliesTheme(definition: preferences?.selectedTheme))
  }
  environment.update(SilliesTheme(definition: preferences.selectedTheme))
  defer {
    NSApp.appearance = originalAppearance
    defaults.removePersistentDomain(forName: suite)
  }
  await preferences.load()
  let session = ChatWindowFixture.makeSession()
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  session.draft = "My draft stays here when I change colors."
  defer { session.finish {} }
  for theme in preferences.themes {
    preferences.themeID = theme.id
    for appearance in [ApplicationAppearance.light, .dark] {
      preferences.appearance = appearance
      NSApp.appearance = appearance.native
      let scheme: ColorScheme = appearance == .dark ? .dark : .light
      try renderSkillInterface(
        ChatSessionView(model: session, openSettings: { _ in }, close: {}, renderer: "cat")
          .environment(
            \.colorScheme, scheme
          ).environment(\.silliesTheme, environment.palette),
        size: ChatWindowLayout.minimumSize, name: "sillies-chat-\(theme.id)-\(appearance.rawValue)")
      try renderSkillInterface(
        ScrollView { AppearanceSettingsPage(model: preferences).padding(24) }
          .background(environment.palette.paper).environment(\.colorScheme, scheme).environment(
            \.silliesTheme, environment.palette),
        size: CGSize(width: 620, height: 620),
        name: "sillies-appearance-\(theme.id)-\(appearance.rawValue)")
      #expect(session.draft == "My draft stays here when I change colors.")
    }
  }
}

@Test @MainActor func independentThemeEnvironmentsKeepWindowsAndEditorsIsolated() async throws {
  let definitions = try await Task.detached { try ThemeCatalog.loadBundled() }.value
  let sillies = try #require(definitions.first { $0.id == "sillies" })
  let dracula = try #require(definitions.first { $0.id == "dracula" })
  let tokyo = try #require(definitions.first { $0.id == "tokyo-night" })
  let firstPalette = SilliesTheme(definition: sillies)
  let secondPalette = SilliesTheme(definition: dracula)
  let first = ThemeEnvironment(palette: firstPalette)
  let second = ThemeEnvironment(palette: secondPalette)
  let environments = [first, second]
  let windows = environments.map { environment in
    let window = NSWindow(
      contentRect: CGRect(x: 50, y: 50, width: 380, height: 240),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    environment.register(window)
    window.contentView = ThemedHostingView(
      rootView: LiveTranscriptTextView(
        text: "Keep my words and selection", followsLive: .constant(false)),
      appearance: environment)
    window.contentView?.layoutSubtreeIfNeeded()
    return window
  }
  defer { for window in windows { window.close() } }
  let firstContent = try #require(windows[0].contentView)
  let secondContent = try #require(windows[1].contentView)
  let firstViewport = try #require(findTranscriptScrollView(in: firstContent))
  let secondViewport = try #require(findTranscriptScrollView(in: secondContent))
  secondViewport.textView.setSelectedRange(NSRange(location: 5, length: 8))
  let originalBackground = windows[1].backgroundColor
  let originalText = secondViewport.textView.textColor
  first.update(SilliesTheme(definition: tokyo))
  for _ in 0..<20 {
    try await Task.sleep(for: .milliseconds(5))
    windows[0].contentView?.layoutSubtreeIfNeeded()
  }
  #expect(first.palette != firstPalette)
  #expect(second.palette == secondPalette)
  #expect(windows[1].backgroundColor == originalBackground)
  #expect(secondViewport.textView.textColor == originalText)
  #expect(secondViewport.textView.selectedRange() == NSRange(location: 5, length: 8))
  #expect(firstViewport.textView.string == "Keep my words and selection")
  #expect(firstViewport.textView.textColor != secondViewport.textView.textColor)
}
