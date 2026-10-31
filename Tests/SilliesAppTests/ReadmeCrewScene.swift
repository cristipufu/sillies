import SilliesCore
import SwiftUI

@testable import SilliesApp

/// A character sheet using the same catalog, rig renderer, and names as the crew picker.
struct ReadmeCrewScene: View {
  private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
  let characters: [CharacterDefinition]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("MEET YOUR WINDOW COMPANY")
        .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.8)
        .foregroundStyle(SilliesTheme.secondary)
      HStack(alignment: .firstTextBaseline) {
        Text("Twelve little personalities.")
          .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.3)
        Spacer()
        Text("Pick your crew.").font(.system(size: 16)).foregroundStyle(SilliesTheme.secondary)
      }
      .padding(.top, 12)
      LazyVGrid(columns: Self.columns, spacing: 30) {
        ForEach(characters) { character in
          portrait(character)
        }
      }
      .padding(.top, 44)
      Spacer(minLength: 0)
      HStack {
        Text("A little mischief between meetings.")
        Spacer()
        Text("SILLIES").tracking(2)
      }
      .font(.system(size: 12, weight: .medium)).foregroundStyle(SilliesTheme.secondary)
    }
    .padding(.horizontal, 76).padding(.vertical, 58)
    .foregroundStyle(SilliesTheme.ink).background(SilliesTheme.paper)
  }

  private func portrait(_ character: CharacterDefinition) -> some View {
    VStack(spacing: 8) {
      CharacterPortrait(renderer: character.renderer, size: 88, registry: RendererRegistry())
        .frame(width: 130, height: 130)
        .background(
          Circle().fill(SilliesTheme.accent.opacity(0.055)).frame(width: 120, height: 120))
      Text(character.name).font(.system(size: 17, weight: .semibold, design: .rounded))
      Text(character.subtitle)
        .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
        .multilineTextAlignment(.center).frame(height: 32, alignment: .top)
    }
    .frame(maxWidth: .infinity)
  }
}
