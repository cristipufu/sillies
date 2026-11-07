import Testing

@testable import SilliesApp

@Test(arguments: ["--validate-catalog", "--writing-fixture", "--input-fixture"])
func noninteractiveLaunchesUseIsolatedApplicationState(_ flag: String) {
  let launch = LaunchConfiguration(arguments: ["Sillies", flag])
  #expect(launch.isAutomatedRun)
  #expect(!launch.showsPreview)
}

@Test func catalogValidationDoesNotRequestAccessibility() {
  let launch = LaunchConfiguration(arguments: ["Sillies", "--validate-catalog"])
  #expect(launch.validatesCatalogOnly)
  #expect(!launch.usesAccessibility)
}

@Test func ordinaryLaunchUsesTheUsersApplicationState() {
  let launch = LaunchConfiguration(arguments: ["Sillies"])
  #expect(!launch.isAutomatedRun)
  #expect(launch.usesAccessibility)
}
