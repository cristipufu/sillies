import CoreGraphics
import Testing

@testable import SilliesCore

private let spacingDisplay = CGRect(x: 0, y: 0, width: 1400, height: 1000)
private let spacingWindow = CGRect(x: 200, y: 150, width: 570, height: 500)

@Test func unoccupiedStoppingSpotsStayWhereTheyWereRequested() throws {
  let surface = spacingSurface()
  let preferred = surface.point(at: 0.35)
  let target = try #require(
    PerchSpacing.nearestAvailablePoint(to: preferred, on: surface, occupied: []))
  #expect(target == preferred)
}

@Test func overlappingStopsMoveToTheNearestFreeSpotWithAGap() throws {
  let surface = spacingSurface()
  let occupied = surface.point(at: 0.5)
  let target = try #require(
    PerchSpacing.nearestAvailablePoint(
      to: occupied, on: surface,
      occupied: [PerchReservation(point: occupied, surface: surface)]))
  #expect(abs(target.x - occupied.x) >= PerchSpacing.separation(between: 64, and: 64) - 0.001)
  #expect(abs(Double(target.y) - surface.y) < 0.001)
  #expect(surface.fraction(for: target) >= 0 && surface.fraction(for: target) <= 1)
}

@Test func verticalClimbersReserveSeparateStopsOnEitherSide() throws {
  for right in [false, true] {
    let window = CGRect(x: 200, y: 30, width: 570, height: 960)
    let surface = PerchSurface(
      window: window, visibleFrame: spacingDisplay, characterSize: 64, preferRight: right)
    #expect(surface.edge == (right ? .right : .left))
    let occupied = surface.point(at: 0.5)
    let target = try #require(
      PerchSpacing.nearestAvailablePoint(
        to: occupied, on: surface,
        occupied: [PerchReservation(point: occupied, surface: surface)]))
    #expect(target.x == surface.start.x)
    #expect(abs(target.y - occupied.y) >= PerchSpacing.separation(between: 64, and: 64) - 0.001)
  }
}

@Test func reservationsUseEachCompanionsActualPresentationSize() throws {
  let large = spacingSurface(size: 112)
  let small = spacingSurface(size: 48)
  let position = large.point(at: 0.5)
  let target = try #require(
    PerchSpacing.nearestAvailablePoint(
      to: position, on: large,
      occupied: [PerchReservation(point: position, surface: small)]))
  #expect(abs(target.x - position.x) >= PerchSpacing.separation(between: 112, and: 48) - 0.001)
}

@Test func unrelatedEdgesDoNotReserveEachOthersSpace() throws {
  let top = spacingSurface()
  let side = PerchSurface(
    window: CGRect(x: 200, y: 30, width: 570, height: 960), visibleFrame: spacingDisplay,
    characterSize: 64)
  let point = top.point(at: 0.5)
  let target = try #require(
    PerchSpacing.nearestAvailablePoint(
      to: point, on: top, occupied: [PerchReservation(point: point, surface: side)]))
  #expect(target == point)
}

@Test func insufficientSpaceWaitsInsteadOfCreatingAnOverlappingStop() {
  let narrow = PerchSurface(
    window: CGRect(x: 200, y: 150, width: 100, height: 500), visibleFrame: spacingDisplay,
    characterSize: 64)
  let point = narrow.point(at: 0.5)
  #expect(
    PerchSpacing.nearestAvailablePoint(
      to: point, on: narrow, occupied: [PerchReservation(point: point, surface: narrow)]) == nil)
}

@Test func pathsCanCrossAnOccupiedSpotWhenTheDestinationIsFree() {
  let surface = spacingSurface()
  let origin = surface.point(at: 0.4)
  let neighbor = CGPoint(x: origin.x + 15, y: origin.y)
  var random = SeededRandom(seed: 1)
  var crossed = false
  for _ in 0..<50 {
    if let plan = StrollPlan(
      from: origin, on: surface, speed: 40, activity: 1, maxDuration: 5,
      occupied: [PerchReservation(point: neighbor, surface: surface)], random: &random),
      plan.target.x > neighbor.x
    {
      crossed = true
      #expect(
        plan.target.x - neighbor.x >= PerchSpacing.separation(between: 64, and: 64) - 0.001)
    }
  }
  #expect(crossed)
}

@Test func fourCompanionsKeepDistinctDestinationsAcrossManyIndependentWalks() {
  for surface in [spacingSurface(), spacingSurface(size: 112)] {
    var stops = (0..<4).map { surface.point(at: Double($0) / 3) }
    var random = SeededRandom(seed: 42)
    for iteration in 0..<1000 {
      let index = iteration % stops.count
      let occupied = stops.enumerated().compactMap { other, point in
        other == index ? nil : PerchReservation(point: point, surface: surface)
      }
      if let plan = StrollPlan(
        from: stops[index], on: surface, speed: 40, activity: 1, maxDuration: 5,
        occupied: occupied, random: &random)
      {
        stops[index] = plan.target
      }
      for first in stops.indices {
        for second in stops.indices where second > first {
          #expect(
            abs(stops[first].x - stops[second].x) + 0.001
              >= PerchSpacing.separation(
                between: surface.presentationSize, and: surface.presentationSize))
        }
      }
    }
  }
}

@Test func greetingsStillTriggerBeforeBodiesWouldOverlap() {
  let distance = PerchSpacing.greetingDistance(for: 64) - 1
  #expect(distance > PerchSpacing.separation(between: 64, and: 64))
  #expect(
    NeighborProximity.nearbyIndices(
      positions: [CGPoint(x: 200, y: 500), CGPoint(x: 200 + distance, y: 500)],
      edges: [.top, .top], size: PerchSpacing.greetingDistance(for: 64)) == [0, 1])
}

private func spacingSurface(size: Double = 64) -> PerchSurface {
  PerchSurface(window: spacingWindow, visibleFrame: spacingDisplay, characterSize: size)
}

@Test func aCrowdedCrewUsesAllAvailableRoomBeforeAnyoneWaits() throws {
  let surface = spacingSurface(size: 112)
  let preferred = (1...4).map { surface.point(at: Double($0) / 5) }
  let result = PerchSpacing.restingPoints(near: preferred, on: surface)
  let points = try result.map { try #require($0) }
  #expect(points.count == 4)
  for index in points.indices.dropFirst() {
    #expect(
      Double(points[index].x - points[index - 1].x) + 0.001
        >= PerchSpacing.separation(between: 112, and: 112))
  }
  #expect(points.first!.x >= surface.start.x && points.last!.x <= surface.end.x)
}

@Test func overcrowdedGroupsWaitOnlyForTheExcessCompanions() {
  let surface = spacingSurface(size: 112)
  let preferred = (1...10).map { surface.point(at: Double($0) / 11) }
  let visible = PerchSpacing.restingPoints(near: preferred, on: surface).compactMap { $0 }
  #expect(visible.count == 4)
  for index in visible.indices.dropFirst() {
    #expect(
      Double(visible[index].x - visible[index - 1].x) + 0.001
        >= PerchSpacing.separation(between: 112, and: 112))
  }
}
