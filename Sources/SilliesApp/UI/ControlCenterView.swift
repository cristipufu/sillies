import SilliesCore
import SwiftUI

struct ControlCenterView: View {
  struct Actions {
    let openSettings: () -> Void
    let openVault: () -> Void
    let quit: () -> Void
  }

  @Environment(\.silliesTheme) private var theme
  let controller: CompanionController
  let actions: Actions

  private static let edgePadding: CGFloat = 20
  private static let crewSpacing: CGFloat = 12
  private static let footerSpacing: CGFloat = 16
  private static let vaultCornerRadius: CGFloat = 14

  var body: some View {
    VStack(spacing: 0) {
      vaultButton.padding(Self.edgePadding)
      crewHeading
      crewPicker
      Divider().padding(.horizontal, Self.edgePadding)
      VStack(spacing: Self.footerSpacing) {
        CompanionControls(settings: controller.settings)
        footer
      }
      .padding(Self.edgePadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.paper)
    .foregroundStyle(theme.ink)
  }

  private var vaultButton: some View {
    Button(action: actions.openVault) {
      HStack(spacing: 12) {
        Image(systemName: "archivebox")
          .font(.system(size: 21, weight: .medium))
          .foregroundStyle(theme.accent)
        VStack(alignment: .leading, spacing: 4) {
          Text("Session Vault").font(.system(.headline, design: .rounded))
          Text("Captures, transcripts & stashes")
            .font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold)).foregroundStyle(theme.secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.card, in: RoundedRectangle(cornerRadius: Self.vaultCornerRadius))
      .contentShape(RoundedRectangle(cornerRadius: Self.vaultCornerRadius))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("crew-vault")
  }

  private var crewHeading: some View {
    HStack {
      Text("Your crew").font(.system(.headline, design: .rounded))
      Spacer()
      Text("\(controller.settings.enabledCharacters.count) selected")
        .font(.caption).foregroundStyle(theme.secondary)
    }
    .padding(.horizontal, Self.edgePadding)
    .padding(.bottom, Self.crewSpacing)
  }

  private var crewPicker: some View {
    ScrollView(.vertical) {
      CompanionGrid(columns: .two, spacing: Self.crewSpacing) {
        ForEach(controller.catalog.characters) { character in
          CompanionCharacterCard(
            character: character,
            isSelected: controller.settings.enabledCharacters.contains(character.id),
            registry: controller.renderers, presentation: .picker
          ) {
            controller.settings.toggleCharacter(character.id)
          }
        }
      }
      .padding(.horizontal, Self.edgePadding)
      .padding(.bottom, Self.edgePadding)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollIndicators(.visible)
    .accessibilityIdentifier("crew-picker")
  }

  private var footer: some View {
    HStack(spacing: Self.footerSpacing) {
      Button {
        controller.settings.paused.toggle()
      } label: {
        Label(
          controller.settings.paused
            ? String(localized: "Resume companions") : String(localized: "Pause companions"),
          systemImage: controller.settings.paused ? "play.fill" : "pause.fill")
      }
      Spacer(minLength: 0)
      Button("Settings", systemImage: "slider.horizontal.3", action: actions.openSettings)
      Button(action: actions.quit) {
        Image(systemName: "power")
      }
      .help("Quit Sillies").accessibilityLabel("Quit Sillies")
    }
    .font(.caption)
    .foregroundStyle(theme.secondary)
    .buttonStyle(.plain)
  }
}

extension Color {
  init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}
