import SilliesCore
import SwiftUI

struct ControlCenterView: View {
  let controller: CompanionController
  let openSettings: () -> Void
  let openPlayground: () -> Void
  var openVault: () -> Void = {}
  let quit: () -> Void

  var body: some View {
    @Bindable var settings = controller.settings
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 11) {
        Image(systemName: "sparkles")
          .font(.system(size: 21, weight: .medium)).foregroundStyle(SilliesTheme.accent)
          .frame(width: 44, height: 44).background(
            SilliesTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
        VStack(alignment: .leading, spacing: 2) {
          Text("sillies").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.9)
          Text("Your workspace, with a little life.").font(.system(size: 11))
            .foregroundStyle(SilliesTheme.secondary)
        }
        Spacer(minLength: 0)
        Button {
          settings.paused.toggle()
        } label: {
          Image(systemName: settings.paused ? "play.fill" : "pause.fill")
            .font(.system(size: 12, weight: .semibold)).frame(width: 31, height: 31)
            .background(SilliesTheme.soft, in: Circle())
        }.buttonStyle(.plain).help(settings.paused ? "Resume companions" : "Pause companions")
          .accessibilityLabel(settings.paused ? "Resume companions" : "Pause companions")
      }

      HStack(spacing: 7) {
        Circle().fill(
          settings.paused || controller.isExcluded
            ? Color.orange : Color(red: 0.40, green: 0.65, blue: 0.49)
        ).frame(width: 6, height: 6)
        Text(controller.restingDescription).font(.system(size: 11, weight: .medium)).lineLimit(1)
          .foregroundStyle(SilliesTheme.secondary)
      }

      HStack {
        if let session = controller.skills.activeAudioSession {
          Button("Open \(session.kind.title)", systemImage: "waveform") {
            controller.skills.onOpenAudioSession?(session)
          }
          Spacer()
          Button("Finish", action: { session.onFinish?() })
        } else {
          Button("Record microphone", systemImage: "mic.fill") {
            controller.startMicrophoneRecording()
          }
          .disabled(!controller.shouldRun || controller.liveCount == 0)
          Spacer()
          Button("Pocket Stash", systemImage: "tray") { openVault() }
        }
      }.font(.system(size: 12, weight: .medium))

      HStack {
        Text("THE LITTLE CREW").font(.system(size: 9, weight: .bold)).tracking(1.5)
        Spacer()
        Text("\(controller.liveCount) of \(controller.catalog.characters.count) out & about")
          .font(.system(size: 10)).foregroundStyle(SilliesTheme.secondary)
      }.padding(.top, 2)

      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
        spacing: 12
      ) {
        ForEach(controller.catalog.characters) { character in
          characterCard(character, enabled: settings.enabledCharacters.contains(character.id)) {
            settings.toggleCharacter(character.id)
          }
        }
      }

      Button {
        controller.greet()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "hand.wave.fill").font(.system(size: 13))
          Text("Say hello").font(.system(size: 12, weight: .semibold))
          Spacer()
          Text("They’re happy you’re here.").font(.system(size: 10)).opacity(0.8)
        }.padding(.horizontal, 14).frame(height: 41)
          .foregroundStyle(.white)
          .background(
            LinearGradient(
              colors: [SilliesTheme.accent, Color(red: 0.63, green: 0.55, blue: 0.81)],
              startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
      }.buttonStyle(.plain).disabled(
        settings.paused || controller.liveCount == 0 || controller.isExcluded)

      VStack(spacing: 14) {
        HStack {
          Label("Hang out", systemImage: "macwindow").font(.system(size: 12, weight: .medium))
          Spacer()
          Picker("Hang out", selection: $settings.followsWindows) {
            Text("Window edges").tag(true)
            Text("Desktop").tag(false)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
        }
        Divider().overlay(SilliesTheme.border.opacity(0.5))
        HStack {
          Label("Energy", systemImage: "leaf").font(.system(size: 12, weight: .medium))
          Spacer()
          Picker("Energy", selection: $settings.activity) {
            ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
          }.labelsHidden().pickerStyle(.segmented).frame(width: 156)
        }
        Divider().overlay(SilliesTheme.border.opacity(0.5))
        HStack(spacing: 12) {
          Label("Size", systemImage: "arrow.up.left.and.arrow.down.right").font(
            .system(size: 12, weight: .medium)
          ).frame(width: 65, alignment: .leading)
          Slider(value: $settings.size, in: AppSettings.minSize...AppSettings.maxSize).tint(
            SilliesTheme.accent
          )
          .accessibilityLabel("Character size")
          Text(sizeLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(
            SilliesTheme.secondary
          ).frame(width: 38)
        }
      }.padding(14).background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 15))
        .overlay(
          RoundedRectangle(cornerRadius: 15).strokeBorder(
            SilliesTheme.border.opacity(0.7), lineWidth: 0.7))

      Button(action: openVault) {
        HStack(spacing: 9) {
          Image(systemName: "archivebox.fill")
            .foregroundStyle(SilliesTheme.accent)
          VStack(alignment: .leading, spacing: 3) {
            Text("Session Vault & Drop Skills").font(.system(size: 11, weight: .semibold))
            Text(
              controller.savedRecordCount == 0
                ? "Drop a sillie on any window to snap, transcribe, or focus."
                : "\(controller.savedRecordCount) saved capture\(controller.savedRecordCount == 1 ? "" : "s"), transcripts & stashes"
            )
            .font(.system(size: 10))
            .foregroundStyle(SilliesTheme.secondary)
            .lineLimit(1)
          }
          Spacer()
          Image(systemName: "arrow.up.right").font(.system(size: 11))
        }.padding(12).background(
          SilliesTheme.card, in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12).strokeBorder(
            SilliesTheme.border.opacity(0.7), lineWidth: 0.7))
      }.buttonStyle(.plain)

      Button(action: openPlayground) {
        HStack(spacing: 9) {
          Image(systemName: "rectangle.dashed.badge.record")
          VStack(alignment: .leading, spacing: 3) {
            Text("Give them a window to play on").font(.system(size: 11, weight: .semibold))
            Text("Drag it. Squeeze it. Watch them hang on.").font(.system(size: 10))
              .foregroundStyle(SilliesTheme.secondary)
          }
          Spacer()
          Image(systemName: "arrow.up.right").font(.system(size: 11))
        }.padding(12).background(
          SilliesTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
      }.buttonStyle(.plain)

      HStack {
        Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Color(hex: "D79B91"))
        Text("A little company. All on your Mac.").font(.system(size: 9)).foregroundStyle(
          SilliesTheme.secondary)
        Spacer()
        Button(action: openSettings) {
          Image(systemName: "slider.horizontal.3").font(.system(size: 12))
        }
        .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
        Button(action: quit) { Image(systemName: "power").font(.system(size: 11)) }
          .buttonStyle(.plain).padding(.leading, 7).help("Quit Sillies").accessibilityLabel(
            "Quit Sillies")
      }
    }.padding(22).frame(width: 388).background(SilliesTheme.paper)
      .foregroundStyle(SilliesTheme.ink)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var sizeLabel: String {
    controller.settings.size < AppSettings.defaultSize
      ? "Tiny"
      : controller.settings.size > AppSettings.largeSizeThreshold ? "Big" : "Little"
  }

  private func characterCard(
    _ character: CharacterDefinition, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 5) {
        ZStack(alignment: .topTrailing) {
          RoundedRectangle(cornerRadius: 12).fill(
            Color(hex: character.accent).opacity(enabled ? 0.13 : 0.05))
          CharacterPortrait(renderer: character.renderer, size: 72, registry: controller.renderers)
            .frame(width: 100, height: 96).frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(enabled ? 1 : 0.4)
          Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15)).foregroundStyle(
              enabled ? SilliesTheme.accent : SilliesTheme.secondary.opacity(0.4)
            )
            .padding(9)
        }.frame(height: 111)
        Text(character.name).font(.system(size: 14, weight: .bold, design: .rounded)).padding(
          .top, 5)
        Text(character.subtitle).font(.system(size: 9)).foregroundStyle(SilliesTheme.secondary)
          .lineLimit(1).minimumScaleFactor(0.85)
      }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 17))
        .overlay(
          RoundedRectangle(cornerRadius: 17).strokeBorder(
            enabled ? SilliesTheme.accent.opacity(0.45) : SilliesTheme.border,
            lineWidth: enabled ? 1.3 : 0.7))
    }.buttonStyle(.plain)
      .accessibilityLabel("\(character.name), \(character.subtitle)")
      .accessibilityValue(enabled ? "Enabled" : "Disabled")
      .help(character.bio)
  }

}

extension Color {
  init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}
