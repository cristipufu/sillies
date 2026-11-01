import Darwin
import Foundation

/// One serial caller owns pipe I/O; cancellation may terminate the process from any executor.
package final class InferenceWorkerConnection: @unchecked Sendable {
  private let exit = WorkerExitSignal()
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private let lock = NSLock()
  private var stopped = false

  package init(executable: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let process = Process()
    let request = Pipe()
    let response = Pipe()
    process.executableURL = executable
    if let language = Bundle.main.preferredLocalizations.first,
      language.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    {
      // Native helper diagnostics follow the app's language rather than its separate defaults domain.
      process.arguments = ["-AppleLanguages", "(\(language))"]
    }
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

  package func send<T: Encodable>(_ request: T, timeout: TimeInterval) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try InferenceWire.write(
      request, to: input, deadline: ProcessInfo.processInfo.systemUptime + timeout)
  }

  package func receive<T: Decodable>(_ type: T.Type, timeout: TimeInterval) throws -> T {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return try InferenceWire.read(
      type, from: output, deadline: ProcessInfo.processInfo.systemUptime + timeout)
  }

  package func stop() {
    lock.withLock {
      guard !stopped else { return }
      stopped = true
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  /// Await process termination without depending on a worker thread's run loop.
  package func reap() async { await exit.waitForCompletion() }

  deinit {
    stop()
    for handle in [input, output] {
      do { try handle.close() } catch {
        fputs("Inference pipe cleanup failed: \(error.localizedDescription)\n", stderr)
      }
    }
  }
}
