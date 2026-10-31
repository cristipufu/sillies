import Foundation

actor WritingFixtureProcess {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private var received = Data()
  private var waiter: CheckedContinuation<WritingFixtureMessage, Error>?
  private static let newline: UInt8 = 10

  func start(executable: URL) throws -> Int32 {
    process.executableURL = executable
    process.arguments = ["--writing-fixture"]
    process.standardInput = input
    process.standardOutput = output
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      Task { await self?.receive(data) }
    }
    try process.run()
    return process.processIdentifier
  }
  func request(_ message: WritingFixtureMessage) async throws -> WritingFixtureMessage {
    var data = try JSONEncoder().encode(message)
    data.append(Self.newline)
    return try await withCheckedThrowingContinuation { continuation in
      waiter = continuation
      do { try input.fileHandleForWriting.write(contentsOf: data) } catch {
        waiter = nil
        continuation.resume(throwing: error)
      }
    }
  }
  func stop() {
    output.fileHandleForReading.readabilityHandler = nil
    if process.isRunning { process.terminate() }
    waiter?.resume(throwing: CancellationError())
    waiter = nil
  }
  private func receive(_ data: Data) {
    guard !data.isEmpty else {
      stop()
      return
    }
    received.append(data)
    guard let end = received.firstIndex(of: Self.newline), let waiter else { return }
    self.waiter = nil
    do {
      waiter.resume(
        returning: try JSONDecoder().decode(
          WritingFixtureMessage.self, from: received.prefix(upTo: end)))
    } catch { waiter.resume(throwing: error) }
    received.removeSubrange(...end)
  }
}
