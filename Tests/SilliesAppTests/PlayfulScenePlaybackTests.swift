import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func playfulEverySceneCompletesWithExteriorPanelsAndCleansUp() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let homes = fixture.companions.map(\.position)
  for scene in fixture.catalog.scenes {
    try fixture.start(scene.id)
    for sample in 0...60 {
      let time = scene.duration * Double(sample) / 60
      fixture.coordinator.advance(at: time)
      for pet in fixture.companions {
        #expect(!pet.panel.frame.intersects(fixture.window), "\(scene.id) at \(time)")
        #expect(!pet.panel.canBecomeKey)
      }
      for (_, propFrame) in fixture.coordinator.propPreviews {
        #expect(!propFrame.intersects(fixture.window))
        #expect(fixture.visible.contains(propFrame))
      }
    }
    #expect(!fixture.coordinator.isActive)
    #expect(!fixture.coordinator.hasVisibleProp)
    #expect(fixture.companions.map(\.position) == homes)
    #expect(fixture.companions.allSatisfy { !$0.isPerformingScene })
  }
}

@Test @MainActor func playfulPickupDuringDescentPreservesPointerAndReturnSlot() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let homeFractions = Dictionary(
    uniqueKeysWithValues: fixture.companions.map {
      ($0.definition.id, $0.surface?.fraction(for: $0.position))
    })
  try fixture.start("edge-climb")
  fixture.coordinator.advance(at: 4)
  let pet = try #require(fixture.companions.first { $0.isPerformingScene })
  let point = pet.position
  let originalFraction = try #require(homeFractions[pet.definition.id] ?? nil)
  fixture.coordinator.cancel(.pickup(pet.definition.id))
  pet.beginPickup(fallbackTarget: nil)
  #expect(pet.position == point)
  #expect(pet.pickupPosition == point)
  #expect((0...1).contains(pet.pickupFraction))
  #expect(pet.pickupFraction == originalFraction)
  pet.endPickup()
}

@Test @MainActor func playfulTravelUsesBoundedNativeFrameWork() throws {
  try measurePlayfulTravel(scene: "edge-climb", startingAt: 1.5)
  try measurePlayfulTravel(scene: "edge-climb", startingAt: 2.6)
  try measurePlayfulTravel(scene: "edge-climb", startingAt: 9.9)
}

@Test @MainActor func playfulSharedTravelUsesBoundedNativeFrameWork() throws {
  try measurePlayfulTravel(scene: "tug-of-war", startingAt: 1.6)
  try measurePlayfulTravel(scene: "parachute", startingAt: 2.6)
}

@MainActor private func measurePlayfulTravel(scene: String, startingAt start: Double) throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  try fixture.start(scene)
  // Present the measured pose before sampling native travel, as the interaction fixtures do.
  fixture.coordinator.advance(at: start)
  try DisplayFrameSequence.presentCreatedWindows()
  var milliseconds: [Double] = []
  try DisplayFrameSequence.run(count: 120) { index in
    let time = start + Double(index) / 120 * 2
    let before = CACurrentMediaTime()
    fixture.coordinator.advance(at: time)
    milliseconds.append((CACurrentMediaTime() - before) * 1000)
  }
  let sorted = milliseconds.sorted()
  let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
  let maximum = sorted.last ?? .infinity
  print("PLAYFUL \(scene): p95=\(p95)ms max=\(maximum)ms")
  #expect(p95 < 1)
  #expect(maximum < 8.33)
}

@Test @MainActor func playfulSceneVisualPreviews() throws {
  guard ProcessInfo.processInfo.environment["SILLIES_PLAYFUL_SNAPSHOTS"] == "1" else { return }
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  for scene in fixture.catalog.scenes {
    var time = 0.0
    for (index, phase) in scene.phases.enumerated() {
      let samples =
        phase.cues.contains { [.cornerPullUp, .cornerLowering].contains($0.travel) }
        ? [0.25, 0.55, 0.65, 0.8, 0.95] : [0.55]
      for progress in samples {
        try fixture.start(scene.id)
        fixture.coordinator.advance(at: time + phase.duration * progress)
        fixture.sampleAnimations(
          at: phase.duration * progress, phase: index, clock: PlayfulPreviewClock())
        try DisplayFrameSequence.presentCreatedWindows()
        let travel = phase.cues.contains { $0.travel == .cornerLowering } ? "lowering" : "pullup"
        let suffix = progress == 0.55 ? "" : "-\(travel)-\(Int(progress * 100))"
        try fixture.snapshot(named: "\(scene.id)-\(index)\(suffix)")
      }
      time += phase.duration
    }
  }
}

@Test @MainActor func playfulClimbingUsesTheWindowBorderWithoutExtraWindows() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  for id in ["edge-climb", "shove", "parachute"] {
    let plan = try fixture.plan(id)
    let session = PlayfulSceneSession(plan: plan, at: 0)
    try fixture.start(id)
    for sample in 0..<200 {
      let time = plan.definition.duration * Double(sample) / 200
      let index = try #require(session.phaseIndex(at: time))
      let phase = plan.definition.phases[index]
      fixture.coordinator.advance(at: time)
      if phase.prop == .none {
        #expect(fixture.coordinator.windowNumbers.isEmpty)
        #expect(fixture.coordinator.propPreviews.isEmpty)
      }
      for actor in session.frames(at: time)
      where actor.pose.isHanging && actor.animation != .hangCatch {
        #expect(abs(actor.gripPoint.x - fixture.window.maxX) < 0.01)
        #expect(actor.gripPoint.y < fixture.window.maxY)
      }
      for pet in fixture.companions where pet.isPerformingScene && pet.attachmentPose.isHanging {
        #expect(!pet.panel.frame.intersects(fixture.window))
        #expect(abs(pet.panel.frame.minX - fixture.window.maxX) < 0.01)
      }
    }
  }
}
