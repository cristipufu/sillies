import Darwin
import Foundation
import WindowMetadataProtocol

/// Bounded pipe I/O, used only by isolated metadata workers. The helper owns its own CG connection.
final class WindowMetadataConnection: @unchecked Sendable {
  private static let responseTimeout: TimeInterval = 2
  private static let millisecondsPerSecond: Double = 1000
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle

  var processIdentifier: Int32 { process.processIdentifier }

  init() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let process = Process()
    let requestPipe = Pipe()
    let responsePipe = Pipe()
    process.executableURL = Self.helperURL
    process.standardInput = requestPipe
    process.standardOutput = responsePipe
    process.standardError = FileHandle.standardError
    try process.run()
    self.process = process
    input = requestPipe.fileHandleForWriting
    output = responsePipe.fileHandleForReading
    guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw POSIXError(.EIO)
    }
    try requestPipe.fileHandleForReading.close()
    try responsePipe.fileHandleForWriting.close()
  }

  private static var helperURL: URL {
    if let path = ProcessInfo.processInfo.environment["SILLIES_METADATA_HELPER"] {
      return URL(fileURLWithPath: path)
    }
    return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SilliesWindowMetadata")
  }

  func stop() {
    if process.isRunning { process.terminate() }
  }

  deinit {
    stop()
    for handle in [input, output] {
      do {
        try handle.close()
      } catch {
        fputs("Window metadata pipe cleanup failed: \(error.localizedDescription)\n", stderr)
      }
    }
  }

  func read(_ request: WindowMetadataRequest) throws -> WindowMetadataSnapshot {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try send(request)
    let deadline = ProcessInfo.processInfo.systemUptime + Self.responseTimeout
    let header = try readExactly(WindowMetadataWire.responseHeaderBytes, before: deadline)
    let length = try WindowMetadataWire.responseLength(from: header)
    let payload = try readExactly(length, before: deadline)
    return try WindowMetadataWire.decode(payload)
  }

  private func send(_ request: WindowMetadataRequest) throws {
    var message = try JSONEncoder().encode(request)
    message.append(WindowMetadataWire.requestTerminator)
    var sent = 0
    while sent < message.count {
      let count = message.withUnsafeBytes { buffer in
        Darwin.write(
          input.fileDescriptor, buffer.baseAddress?.advanced(by: sent), message.count - sent)
      }
      if count < 0, errno == EINTR { continue }
      if count < 0, errno == EPIPE { throw WindowMetadataError.connectionClosed }
      guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      sent += count
    }
  }

  private func readExactly(_ count: Int, before deadline: TimeInterval) throws -> Data {
    var data = Data(count: count)
    var received = 0
    while received < count {
      try waitUntilReadable(before: deadline)
      let readCount = data.withUnsafeMutableBytes { buffer in
        Darwin.read(
          output.fileDescriptor, buffer.baseAddress?.advanced(by: received), count - received)
      }
      if readCount < 0, errno == EINTR { continue }
      if readCount < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      guard readCount > 0 else { throw WindowMetadataError.connectionClosed }
      received += readCount
    }
    return data
  }

  private func waitUntilReadable(before deadline: TimeInterval) throws {
    while true {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { throw WindowMetadataError.responseTimedOut }
      var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
      let readiness = poll(&descriptor, 1, Int32(ceil(remaining * Self.millisecondsPerSecond)))
      if readiness < 0, errno == EINTR { continue }
      if readiness < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      guard readiness > 0 else { throw WindowMetadataError.responseTimedOut }
      return
    }
  }
}
