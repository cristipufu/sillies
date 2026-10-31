import Darwin
import Foundation

/// One serial caller owns pipe I/O; cancellation may terminate the process from any executor.
final class TextWorkerConnection: @unchecked Sendable {
  private static let responseTimeout: TimeInterval = 120
  private let exit = WorkerExitSignal()
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private let lock = NSLock()
  private var stopped = false

  init(executable: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let process = Process()
    let request = Pipe()
    let response = Pipe()
    process.executableURL = executable
    process.standardInput = request
    process.standardOutput = response
    process.standardError = FileHandle.standardError
    process.qualityOfService = .utility
    let exit = exit
    process.terminationHandler = { _ in exit.complete() }
    try process.run()
    self.process = process
    input = request.fileHandleForWriting
    output = response.fileHandleForReading
    guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1,
      fcntl(input.fileDescriptor, F_SETFL, O_NONBLOCK) != -1
    else {
      process.terminate()
      throw POSIXError(.EIO)
    }
    try request.fileHandleForReading.close()
    try response.fileHandleForWriting.close()
  }

  func generate(_ request: TextInferenceRequest) throws -> String {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try TextInferenceWire.write(
      request, to: input, deadline: ProcessInfo.processInfo.systemUptime + Self.responseTimeout)
    let response = try TextInferenceWire.read(
      TextInferenceResponse.self, from: output,
      deadline: ProcessInfo.processInfo.systemUptime + Self.responseTimeout)
    if let failure = response.failure { throw TextModelError.unavailable(failure) }
    guard let text = response.text, !text.isEmpty else { throw TextModelError.invalidResponse }
    return text
  }

  func stop() {
    lock.withLock {
      guard !stopped else { return }
      stopped = true
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  /// Await process termination without depending on a worker thread's run loop.
  func reap() async { await exit.waitForCompletion() }

  deinit {
    stop()
    for handle in [input, output] {
      do { try handle.close() } catch {
        fputs("Text model pipe cleanup failed: \(error.localizedDescription)\n", stderr)
      }
    }
  }
}
