import SilliesCore
import SwiftUI

struct CompanionCharacterCard: View {
  enum Presentation {
    case gallery
    case picker

    var portraitSize: Double { self == .gallery ? 82 : 58 }
    var artworkHeight: CGFloat { self == .gallery ? 122 : 86 }
    var cornerRadius: CGFloat { self == .gallery ? 18 : 14 }
    var selectionSize: CGFloat { self == .gallery ? 23 : 20 }
    var selectionInset: CGFloat { self == .gallery ? 10 : 8 }
    var nameSize: CGFloat { self == .gallery ? 15 : 13 }
    var captionPadding: CGFloat { self == .gallery ? 14 : 12 }
  }

  @Environment(\.silliesTheme) private var theme
  @State private var isHovered = false
  let character: CharacterDefinition
  let isSelected: Bool
  let registry: RendererRegistry
  let presentation: Presentation
  let action: () -> Void

  private static let captionHeight: CGFloat = 32
  private static let captionSpacing: CGFloat = 4
  private static let captionInset: CGFloat = 10
  private static let captionSize: CGFloat = 11
  private static let artworkWashOpacity = 0.09
  private static let selectionGlyphScale = 0.43
  private static let selectionBorder: CGFloat = 0.8

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        artwork
        caption
      }
      .frame(maxWidth: .infinity)
      .contentShape(RoundedRectangle(cornerRadius: presentation.cornerRadius))
    }
    .buttonStyle(
      CompanionCardButtonStyle(
        isSelected: isSelected, isHovered: isHovered, cornerRadius: presentation.cornerRadius)
    )
    .onHover { isHovered = $0 }
    .accessibilityLabel("\(character.name), \(LocalizedCatalogText.value(character.subtitle))")
    .accessibilityValue(
      isSelected ? String(localized: "Selected") : String(localized: "Not selected")
    )
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .help(LocalizedCatalogText.value(character.bio))
  }

  private var artwork: some View {
    let accent = Color(hex: character.accent)
    return CharacterPortrait(
      renderer: character.renderer, size: presentation.portraitSize, registry: registry
    )
    .frame(width: presentation.artworkHeight, height: presentation.artworkHeight)
    .frame(maxWidth: .infinity)
    .frame(height: presentation.artworkHeight)
    .background(
      LinearGradient(
        colors: [accent.opacity(Self.artworkWashOpacity), .clear],
        startPoint: .top, endPoint: .bottom)
    )
    .overlay(alignment: .topTrailing) {
      selectionMark.padding(presentation.selectionInset)
    }
    .accessibilityHidden(true)
  }

  private var caption: some View {
    VStack(spacing: Self.captionSpacing) {
      Text(character.name)
        .font(.system(size: presentation.nameSize, weight: .bold, design: .rounded))
        .foregroundStyle(theme.ink)
        .lineLimit(1)
      Text(LocalizedCatalogText.value(character.subtitle))
        .font(.system(size: Self.captionSize))
        .foregroundStyle(theme.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(height: Self.captionHeight, alignment: .top)
    }
    .padding(.horizontal, Self.captionInset)
    .padding(.bottom, presentation.captionPadding)
  }

  private var selectionMark: some View {
    Image(systemName: isSelected ? "checkmark" : "plus")
      .font(.system(size: presentation.selectionSize * Self.selectionGlyphScale, weight: .bold))
      .foregroundStyle(isSelected ? theme.onAccent : theme.secondary)
      .frame(width: presentation.selectionSize, height: presentation.selectionSize)
      .background(isSelected ? theme.accentFill : theme.card, in: Circle())
      .overlay(
        Circle().strokeBorder(isSelected ? .clear : theme.border, lineWidth: Self.selectionBorder))
  }
}
