import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

/// Native, offscreen previews of every card, including the rows below the Settings viewport.
@Test @MainActor func exportCompanionCardPreviews() throws {
  guard ProcessInfo.processInfo.environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1" else { return }
  let characters = try CharacterCatalog().characters
  let registry = RendererRegistry()
  let previousAppearance = NSApp.appearance
  defer { NSApp.appearance = previousAppearance }
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSApp.appearance = NSAppearance(named: appearance)
    for presentation in [CompanionCharacterCard.Presentation.gallery, .picker] {
      let isGallery = presentation == .gallery
      let view = CompanionCardPreview(
        characters: characters, registry: registry, presentation: presentation)
      let width: CGFloat = isGallery ? 619 : 420
      let measurement = NSHostingController(rootView: view)
      // This artifact contains every row, including companions below the real scroll viewport.
      let contentSize = measurement.sizeThatFits(in: CGSize(width: width, height: 0))
      try renderSkillInterface(
        view,
        size: CGSize(width: width, height: ceil(contentSize.height)),
        name: "sillies-crew-\(isGallery ? "gallery" : "picker")-\(appearance.rawValue)")
    }
  }
}

private struct CompanionCardPreview: View {
  @Environment(\.silliesTheme) private var theme
  let characters: [CharacterDefinition]
  let registry: RendererRegistry
  let presentation: CompanionCharacterCard.Presentation
  private let selected: Set<String> = ["mochi", "pogo", "lumi", "flick"]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if presentation == .gallery {
        HStack {
          Text("Your crew").font(.system(size: 22, weight: .bold, design: .rounded))
          Spacer()
          Text("4 selected").font(.caption).foregroundStyle(theme.secondary)
        }
      }
      CompanionGrid(columns: presentation == .gallery ? .four : .two, spacing: 12) {
        ForEach(characters) { character in
          CompanionCharacterCard(
            character: character, isSelected: selected.contains(character.id), registry: registry,
            presentation: presentation, action: {})
        }
      }
    }
    .padding(presentation == .gallery ? 28 : 22)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(theme.paper)
  }
}
