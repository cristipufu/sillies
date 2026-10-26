import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

private actor IconLoadProbe {
  private(set) var calls = 0
  private var waiting: [CheckedContinuation<CGImage?, Never>] = []

  func load() async -> CGImage? {
    calls += 1
    return await withCheckedContinuation { waiting.append($0) }
  }

  func finish(_ pixels: CGImage?) {
    let pending = waiting
    waiting.removeAll()
    for continuation in pending { continuation.resume(returning: pixels) }
  }
}

@Test @MainActor func iconRenderingOnlyReadsCacheAndDuplicateLoadsAreCoalesced() async throws {
  let probe = IconLoadProbe()
  let cache = ApplicationIconCache(load: { _ in await probe.load() })
  let target = iconTestTarget()
  for _ in 0..<100 { #expect(cache.image(for: target) == nil) }
  #expect(await probe.calls == 0)
  for _ in 0..<100 { cache.prepare(for: target) }
  try await waitForIcon { await probe.calls == 1 }
  let context = try #require(
    CGContext(
      data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  await probe.finish(context.makeImage())
  try await waitForIcon { cache.image(for: target) != nil }
  for _ in 0..<100 { cache.prepare(for: target) }
  #expect(await probe.calls == 1)
  cache.cancelPending()
}

@Test @MainActor func unavailableIconsAreCachedWithoutRepeatedLaunchServicesRequests() async throws
{
  let probe = IconLoadProbe()
  let cache = ApplicationIconCache(load: { _ in await probe.load() })
  let target = iconTestTarget()
  cache.prepare(for: target)
  try await waitForIcon { await probe.calls == 1 }
  await probe.finish(nil)
  for _ in 0..<10 {
    try await Task.sleep(for: .milliseconds(1))
    cache.prepare(for: target)
  }
  #expect(await probe.calls == 1)
  #expect(cache.image(for: target) == nil)
  cache.cancelPending()
}

@Test @MainActor func cancelledIconLoadsCannotUpdateViewsAfterPause() async throws {
  let probe = IconLoadProbe()
  let cache = ApplicationIconCache(load: { _ in await probe.load() })
  let target = iconTestTarget()
  cache.prepare(for: target)
  try await waitForIcon { await probe.calls == 1 }
  cache.cancelPending()
  let context = try #require(
    CGContext(
      data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  await probe.finish(context.makeImage())
  try await Task.sleep(for: .milliseconds(5))
  #expect(cache.image(for: target) == nil)
}

private func iconTestTarget() -> WindowTargetCandidate {
  WindowTargetCandidate(windowID: 1, processID: 100, appName: "Test", frame: .zero)
}

@MainActor
private func waitForIcon(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(1))
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  let satisfied = await condition()
  #expect(satisfied, "Timed out waiting for an icon load")
}
