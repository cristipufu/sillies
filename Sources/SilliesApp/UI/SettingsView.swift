import SwiftUI

struct SettingsView: View {
  let controller: CompanionController
  var speechModels: SpeechModelsPresentation? = nil
  var shortcuts: CommandShortcuts? = nil
  var loginItems: LoginItemSettings? = nil
  var writingTools: WritingTools? = nil
  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }

  var body: some View {
    @Bindable var settings = controller.settings
    ScrollView {
      VStack(alignment: .leading, spacing: 25) {
        HStack(spacing: 15) {
          CharacterPortrait(
            renderer: controller.catalog.characters.first?.renderer ?? "cat",
            size: 57, registry: controller.renderers
          ).frame(width: 73, height: 73)
          VStack(alignment: .leading, spacing: 5) {
            Text("Make yourself at home.").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("A few small things, just the way you like them.").font(.system(size: 12))
              .foregroundStyle(SilliesTheme.secondary)
          }
        }
        if let shortcuts, let loginItems {
          settingsSection("EVERYDAY SHORTCUTS") {
            CommandSettingsView(shortcuts: shortcuts, login: loginItems)
          }
        }
        if let writingTools {
          settingsSection("DICTATION & WRITING") { DictationSettingsView(tools: writingTools) }
        }
        settingsSection("THEIR LITTLE WORLD") {
          Toggle("Follow the active window", isOn: $settings.followsWindows)
          Text(
            "They walk the top of your focused window. Tall windows get outside edge seats. Your document stays clear. No permission setup needed."
          )
          .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
          Divider()
          Toggle("Reduce motion", isOn: $settings.reduceMotion)
          Text(
            "Keeps the crew still, with gentle changes of expression. Your Mac’s Reduce Motion preference is also respected."
          )
          .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
        }
        settingsSection("SOME SPACE TO FOCUS") {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(controller.tracker.applicationName).fontWeight(.medium)
              Text("Companions can take a break in selected apps.").font(.system(size: 11))
                .foregroundStyle(SilliesTheme.secondary)
            }
            Spacer()
            Button(controller.isExcluded ? "Show here" : "Hide here") {
              controller.toggleCurrentApplicationExclusion()
            }
            .buttonStyle(SoftButtonStyle()).disabled(controller.tracker.bundleIdentifier == nil)
          }
          if !settings.excludedApplications.isEmpty {
            Divider()
            ForEach(settings.excludedApplications.sorted(), id: \.self) { bundle in
              HStack {
                Text(bundle).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                Spacer()
                Button {
                  settings.excludedApplications.remove(bundle)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(SilliesTheme.secondary)
                .accessibilityLabel("Remove exclusion for \(bundle)")
              }
            }
          }
        }
        settingsSection("DROP-TO-BIND SKILLS") {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Window skills & Session Vault").fontWeight(.medium)
              Text(
                "Pause while dragging a companion over a window to choose Listen, Participate, Snap, Explain, or Record. Right-click a companion for the same skills and Save Clipboard. Add text and links directly in Pocket Stash."
              )
              .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
            }
            Spacer(minLength: 12)
            Button("Open Vault") {
              controller.onOpenVault?(nil)
            }
            .buttonStyle(SoftButtonStyle())
          }
        }
        settingsSection("ON YOUR MAC, IN YOUR CORNER") {
          Label("Everything happens locally.", systemImage: "lock.shield").fontWeight(.medium)
          Text(
            "Sillies observes window positions and activity signals. On-device OCR snapshots and audio transcription run only when you explicitly start a window skill, and stay in your local Session Vault."
          )
          .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
          HStack {
            Circle().fill(Color.green).frame(
              width: 6, height: 6)
            Text(
              controller.tracker.hasAccessibility
                ? "Window following + enhanced app reactions" : "Window following is ready"
            ).font(.system(size: 11))
            Spacer()
            Button("Enhanced reactions") {
              controller.tracker.requestAccessibility()
              if !controller.tracker.hasAccessibility {
                controller.tracker.openAccessibilitySettings()
              }
            }.buttonStyle(
              SoftButtonStyle())
          }.padding(.top, 4)
        }
        if let speechModels {
          settingsSection("TRANSCRIPTION MODELS") {
            SpeechModelSettingsView(
              model: speechModels, activeModelID: controller.activeSpeechModelID,
              activeDiarizationModelID: controller.activeDiarizationModelID)
          }
        }
        settingsSection("UPDATES") {
          UpdatesSettingsView()
        }
        DisclosureGroup("Behind the scenes") {
          VStack(spacing: 9) {
            diagnostic("Companions", value: "\(controller.liveCount)")
            diagnostic(
              "Movement clock",
              value: controller.movingCount == 0 ? "Stopped" : "\(controller.movingCount) moving")
            diagnostic("Power mode", value: controller.tracker.isLowPower ? "Low Power" : "Normal")
            diagnostic("Recent reaction", value: controller.lastReaction)
            diagnostic("Activity events", value: "\(controller.tracker.receivedEvents)")
          }.font(.system(size: 11)).padding(.top, 12)
        }.font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
        Text("Sillies · \(appVersion)\nLittle companions. Big personalities.")
          .font(.system(size: 10)).foregroundStyle(SilliesTheme.secondary).frame(
            maxWidth: .infinity
          ).multilineTextAlignment(.center)
      }.padding(28)
    }.frame(width: 560, height: 690).background(SilliesTheme.paper).foregroundStyle(
      SilliesTheme.ink
    )
    .tint(SilliesTheme.accent)
  }

  private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 11) {
      Text(title).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(
        SilliesTheme.secondary)
      VStack(alignment: .leading, spacing: 12, content: content)
        .font(.system(size: 12)).padding(17).frame(maxWidth: .infinity, alignment: .leading)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 15))
        .overlay(
          RoundedRectangle(cornerRadius: 15).strokeBorder(SilliesTheme.border, lineWidth: 0.6))
    }
  }

  private func diagnostic(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value).monospacedDigit()
    }
  }
}
