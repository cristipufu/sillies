import AppKit
import SwiftUI
import Testing

@testable import SilliesApp

@Test func catalogFiltersKeepActiveDownloadsAndFailuresReachable() {
  #expect(ModelCatalogFilter.installed.includes(.ready))
  #expect(!ModelCatalogFilter.available.includes(.ready))
  #expect(!ModelCatalogFilter.installed.includes(.absent))
  #expect(ModelCatalogFilter.available.includes(.absent))
  for filter in ModelCatalogFilter.allCases {
    for state in [
      ModelInstallationState.downloading(0.3), .verifying(0.8), .cancelling,
      .failed("Download interrupted"), .preparing, .preparationFailed("Preparation failed"),
    ] {
      #expect(filter.includes(state))
    }
  }
  #expect(!ModelCatalogFilter.installed.includes(.paused))
  #expect(ModelCatalogFilter.available.includes(.paused))
}

@Test @MainActor func modelCatalogShowsProgressAndRecoveryAtMinimumSettingsWidth() throws {
  let entries: [ModelCatalogEntry<String>] = [
    .init(
      id: "installed", family: "Example", name: "Small model", detail: "2 GB · 8 GB memory",
      state: .ready, isSelected: true, model: "Ready"),
    .init(
      id: "progress", family: "Example", name: "Downloading model", detail: "4 GB · 16 GB memory",
      state: .verifying(0.72), isSelected: false, model: "Checking downloaded files"),
    .init(
      id: "failure", family: "Standalone", name: "Standalone",
      detail: "Multiple languages",
      state: .failed("Download interrupted"), isSelected: false, model: "Try again"),
  ]
  for mode in [NSAppearance.Name.aqua, .darkAqua] {
    let previous = NSApp.appearance
    NSApp.appearance = NSAppearance(named: mode)
    defer { NSApp.appearance = previous }
    try renderSkillInterface(
      ModelCatalogBrowser(entries: entries) { text in
        VStack(alignment: .leading) {
          Text(text)
          Button("Download") {}
        }
      }.padding(20), size: CGSize(width: 560, height: 560),
      name: "sillies-catalog-states-\(mode.rawValue)")
  }
}

@Test @MainActor func settingsGroupsCoverEachDestinationOnceAndProfilesDoNotRestartSetup() {
  let destinations = SettingsGroup.allCases.flatMap(\.destinations)
  #expect(Set(destinations) == Set(SettingsDestination.allCases))
  #expect(destinations.count == SettingsDestination.allCases.count)
  let navigation = SettingsNavigation()
  navigation.returnsToSetup = true
  navigation.showProfile("pogo")
  #expect(navigation.selectedCompanionID == "pogo")
  #expect(navigation.destination == .companions && navigation.companionsPage == .profile)
  #expect(!navigation.returnsToSetup)
}
