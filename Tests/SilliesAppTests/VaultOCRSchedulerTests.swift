import Foundation
import Testing

@testable import SilliesApp

private actor OCRFixture {
  var calls = 0
  var continuation: CheckedContinuation<String, Never>?
  func recognize() async -> String {
    calls += 1
    return await withCheckedContinuation { continuation = $0 }
  }
  func complete(_ text: String) {
    continuation?.resume(returning: text)
    continuation = nil
  }
}

@Test @MainActor func backgroundOCRSeesWorkAddedDuringAnEmptyQueueRead() async throws {
  let queue = DelayedOCRQueue()
  let scheduler = VaultOCRScheduler(recognize: { _ in "recognized" })
  scheduler.next = { await queue.next() }
  scheduler.complete = { _, result in await queue.complete(result) }
  scheduler.pump()
  for _ in 0..<100 {
    if await queue.isReading { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(await queue.isReading)
  await queue.addRequest()
  scheduler.pump()
  await queue.finishEmptyRead()
  for _ in 0..<100 {
    if await queue.delivered { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(await queue.delivered)
  scheduler.stop()
}

private actor DelayedOCRQueue {
  private var reading: CheckedContinuation<VaultOCRScheduler.Request?, Never>?
  private var reads = 0
  private var pending: VaultOCRScheduler.Request?
  private(set) var delivered = false
  var isReading: Bool { reading != nil }
  func next() async -> VaultOCRScheduler.Request? {
    reads += 1
    if reads == 1 { return await withCheckedContinuation { reading = $0 } }
    return pending
  }
  func addRequest() {
    pending = .init(id: UUID(), url: URL(fileURLWithPath: "/fixture.png"), revision: UUID())
  }
  func finishEmptyRead() {
    reading?.resume(returning: nil)
    reading = nil
  }
  func complete(_ result: Result<String, Error>) {
    if case .success("recognized") = result { delivered = true }
    pending = nil
  }
}

@Test @MainActor func backgroundOCRNeverOverlapsOrPublishesCanceledWork() async throws {
  let fixture = OCRFixture()
  let scheduler = VaultOCRScheduler(recognize: { _ in await fixture.recognize() })
  let request = VaultOCRScheduler.Request(
    id: UUID(), url: URL(fileURLWithPath: "/fixture.png"), revision: UUID())
  var pending = true
  var delivered: [String] = []
  scheduler.next = { pending ? request : nil }
  scheduler.complete = { _, result in
    if case .success(let text) = result { delivered.append(text) }
    pending = false
  }
  scheduler.pump()
  for _ in 0..<100 {
    if await fixture.calls == 1 { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  scheduler.stop()
  scheduler.resume()
  #expect(await fixture.calls == 1)
  await fixture.complete("canceled")
  for _ in 0..<100 {
    if await fixture.calls == 2 { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(delivered.isEmpty)
  await fixture.complete("Ștefan’s screenshot")
  for _ in 0..<100 {
    if !delivered.isEmpty { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(delivered == ["Ștefan’s screenshot"])
  #expect(await fixture.calls == 2)
  scheduler.stop()
}
