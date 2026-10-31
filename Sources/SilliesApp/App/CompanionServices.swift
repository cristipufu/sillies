/// Runtime collaborators and native-access policy, independent of character assets.
@MainActor
struct CompanionServices {
  var accessibility: WorkspaceTracker.Accessibility = .enabled
  var skills: SkillCoordinator
  var eventProducers: [any WorkspaceEventProducer] = []
}
