import AppKit
import Sparkle
import SwiftUI

/// Manages Sparkle updates signed with EdDSA (`SUPublicEDKey`).
@MainActor
final class Updates {
  static let shared = Updates()

  let controller: SPUStandardUpdaterController?

  private init() {
    let args = ProcessInfo.processInfo.arguments
    let isAutomated =
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || args.contains {
        $0.hasPrefix("--") || $0.contains("swift-testing") || $0.hasSuffix(".xctest")
      }
    let configured =
      !isAutomated
      && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
      && Bundle.main.bundleURL.pathExtension == "app"
    controller =
      configured
      ? SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
      : nil
  }

  var updater: SPUUpdater? { controller?.updater }

  var canCheck: Bool { updater?.canCheckForUpdates ?? false }

  func checkNow(_ sender: Any? = nil) {
    controller?.checkForUpdates(sender)
  }
}

struct UpdatesSettingsView: View {
  @State private var automaticallyChecks =
    Updates.shared.updater?.automaticallyChecksForUpdates ?? false
  @State private var automaticallyDownloads =
    Updates.shared.updater?.automaticallyDownloadsUpdates ?? false

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }

  var body: some View {
    if let updater = Updates.shared.updater {
      Toggle(
        "Check for updates automatically",
        isOn: Binding(
          get: { automaticallyChecks },
          set: {
            automaticallyChecks = $0
            updater.automaticallyChecksForUpdates = $0
          })
      )
      Text("Once a day, Sillies checks GitHub Releases for a signed update.")
        .font(.system(size: 11))
        .foregroundStyle(SilliesTheme.secondary)
      Divider()
      Toggle(
        "Download and install updates automatically",
        isOn: Binding(
          get: { automaticallyDownloads },
          set: {
            automaticallyDownloads = $0
            updater.automaticallyDownloadsUpdates = $0
          })
      )
      .disabled(!automaticallyChecks)
      Divider()
      HStack {
        Text("Version \(appVersion)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
        Spacer()
        Button("Check for Updates…") {
          Updates.shared.checkNow()
        }
        .buttonStyle(SoftButtonStyle())
        .disabled(!Updates.shared.canCheck)
      }
    } else {
      HStack {
        Text("Updates are checked automatically in signed release builds (v\(appVersion)).")
          .font(.system(size: 11))
          .foregroundStyle(SilliesTheme.secondary)
        Spacer()
      }
    }
  }
}
