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
  try fixture.start("rope-descent")
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
  try measurePlayfulTravel(scene: "rope-descent", startingAt: 2.6)
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
      try fixture.start(scene.id)
      fixture.coordinator.advance(at: time + phase.duration * 0.55)
      fixture.sampleAnimations(
        at: phase.duration * 0.55, phase: index, clock: PlayfulPreviewClock())
      try DisplayFrameSequence.presentCreatedWindows()
      try fixture.snapshot(named: "\(scene.id)-\(index)")
      time += phase.duration
    }
  }
}

@Test @MainActor func playfulRopeStaysConnectedToTheMarginAndBothHands() throws {
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let definition = try #require(fixture.catalog.scenes.first { $0.id == "rope-descent" })
  let pet = try #require(fixture.companions.last)
  let participant = PlayfulSceneParticipant(
    id: pet.definition.id, profile: try #require(pet.definition.playful),
    surface: try #require(pet.surface), position: pet.position, windowID: pet.attachedWindowID)
  let plan = try #require(
    PlayfulSceneLayout.plan(
      .init(
        definition: definition, participants: [participant], bystanders: [],
        window: fixture.window, visibleFrame: fixture.visible, message: "")))
  let session = PlayfulSceneSession(plan: plan, at: 0)
  for sample in 0..<200 {
    let time = definition.duration * Double(sample) / 200
    let index = try #require(session.phaseIndex(at: time))
    guard definition.phases[index].prop == .descentRope else { continue }
    let frames = session.frames(at: time)
    let actor = try #require(frames.first)
    let frame = try #require(
      PlayfulPropLayout.frame(
        for: .init(
          prop: .descentRope, frames: frames, plan: plan, textSize: .zero)))
    let rope = PlayfulPropLayout.rope(in: frame, actor: actor, window: fixture.window)
    let top = try #require(PlayfulPropLayout.ropeTopFrame(actor: actor, plan: plan))
    #expect(top.minY == fixture.window.maxY && top.minX < fixture.window.maxX)
    #expect(!top.intersects(fixture.window))
    #expect(rope.cornerStart.x + frame.minX < fixture.window.maxX)
    #expect(rope.cornerStart.y + frame.minY > fixture.window.maxY)
    guard actor.pose.isHanging, actor.animation != .hangCatch else { continue }
    let grip = CGPoint(x: actor.gripPoint.x - frame.minX, y: actor.gripPoint.y - frame.minY)
    #expect(abs(rope.strand.midX - grip.x) < 0.01)
    #expect(rope.strand.minY <= grip.y && rope.strand.maxY >= grip.y)
    #expect(rope.strand.minY <= grip.y - 0.29 * participant.surface.presentationSize)
    #expect(abs(rope.strand.midX - rope.cornerEnd.x) < 0.01)
    #expect(rope.strand.minY <= rope.cornerEnd.y && rope.strand.maxY >= rope.cornerEnd.y)
    #expect(frame.minX == fixture.window.maxX)
    #expect(!frame.intersects(fixture.window))
  }
}
