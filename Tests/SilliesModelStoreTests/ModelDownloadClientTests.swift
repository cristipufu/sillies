import Foundation
import Synchronization
import XCTest

@testable import SilliesModelStore

final class ModelDownloadClientTests: XCTestCase, @unchecked Sendable {
  func testCancellationBeforeStartingPreservesExistingResumeData() async throws {
    let request = makeRequest(try XCTUnwrap(URL(string: "http://127.0.0.1:1/unused")), count: 1) {
      _ in
      XCTFail("Cancelled transfer started")
    }
    let previous = Data("saved resume data".utf8)
    try previous.write(to: request.resumeFile)
    defer { remove(request.resumeFile) }
    let transfer = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await ModelDownloadClient().download(request)
    }
    do {
      let file = try await transfer.value
      remove(file)
      XCTFail("Cancelled transfer succeeded")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(try Data(contentsOf: request.resumeFile), previous)
  }

  func testRealTransferReportsIntermediateBytesAndRetainsTheFile() async throws {
    let server = try DownloadHTTPFixture()
    defer { server.stop() }
    let url = try await server.start()
    let progress = Mutex<[Int64]>([])
    let request = makeRequest(url, count: server.data.count) { bytes in
      XCTAssertFalse(Thread.isMainThread)
      progress.withLock { $0.append(bytes) }
    }
    let file = try await ModelDownloadClient().download(request)
    defer {
      remove(file)
      remove(request.resumeFile)
    }
    XCTAssertEqual(try Data(contentsOf: file), server.data)
    let values = progress.withLock { $0 }
    XCTAssertTrue(
      values.contains { $0 > 0 && $0 < server.data.count }, "No in-flight byte progress")
    XCTAssertEqual(values, values.sorted())
    XCTAssertEqual(values.last, Int64(server.data.count))
  }

  func testPauseProducesResumeDataAndResumeCompletes() async throws {
    let server = try DownloadHTTPFixture()
    defer { server.stop() }
    let url = try await server.start()
    let (events, signal) = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let request = makeRequest(url, count: server.data.count) { signal.yield($0) }
    defer {
      signal.finish()
      remove(request.resumeFile)
    }
    let transfer = Task { try await ModelDownloadClient().download(request) }
    for await bytes in events where bytes > 0 { break }
    transfer.cancel()
    do {
      let file = try await transfer.value
      remove(file)
      XCTFail("Cancelled transfer succeeded")
    } catch { XCTAssertEqual((error as NSError).code, NSURLErrorCancelled) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: request.resumeFile.path))
    let file = try await ModelDownloadClient().download(request)
    defer { remove(file) }
    XCTAssertEqual(try Data(contentsOf: file), server.data)
    XCTAssertFalse(FileManager.default.fileExists(atPath: request.resumeFile.path))
  }

  func testOversizedTransferFailsWithoutPublishingOversizedProgress() async throws {
    let server = try DownloadHTTPFixture()
    defer { server.stop() }
    let url = try await server.start()
    let count = DownloadHTTPFixture.chunkBytes
    let request = makeRequest(url, count: count) { XCTAssertLessThanOrEqual($0, Int64(count)) }
    defer { remove(request.resumeFile) }
    do {
      let file = try await ModelDownloadClient().download(request)
      remove(file)
      XCTFail("Oversized transfer succeeded")
    } catch ModelStoreError.invalidArtifact {} catch { XCTFail("Unexpected error: \(error)") }
  }

  private func makeRequest(_ url: URL, count: Int, progress: @escaping @Sendable (Int64) -> Void)
    -> ModelDownloadRequest
  {
    .init(
      artifact: .init(path: "weights.bin", url: url, byteCount: Int64(count), sha256: "unused"),
      resumeFile: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).resume"),
      progress: progress)
  }

  private func remove(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do { try FileManager.default.removeItem(at: url) } catch { XCTFail("Cleanup failed: \(error)") }
  }
}
