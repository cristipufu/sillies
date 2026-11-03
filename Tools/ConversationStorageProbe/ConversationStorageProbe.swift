import Foundation
import SilliesConversationTestSupport

@main struct ConversationStorageProbe {
  private static let interruptionDeadline: Duration = .seconds(30)

  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      try await Task.detached(priority: .utility) { try await run(arguments) }.value
    } catch {
      fputs("Conversation storage probe failed: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func run(_ arguments: [String]) async throws {
    guard arguments.count >= 2 else { throw ProbeError.arguments }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
    switch arguments[0] {
    case "seed":
      guard arguments.count == 3, let count = Int(arguments[2]) else { throw ProbeError.arguments }
      let started = ContinuousClock.now
      let fixture = try StoredConversationFixture.seed(at: directory, count: count)
      print("SEEDED \(fixture.messageCount) messages in \(started.duration(to: .now))")
    case "hold-transaction":
      guard arguments.count == 2 else { throw ProbeError.arguments }
      _ = try ConversationRecoveryFixture.commit(at: directory)
      let transaction = try InterruptedConversationTransaction(directory: directory)
      defer { withExtendedLifetime(transaction) {} }
      try await Task.sleep(for: interruptionDeadline)
      throw ProbeError.supervisorDidNotInterrupt
    default: throw ProbeError.arguments
    }
  }
}

private enum ProbeError: Error { case arguments, supervisorDidNotInterrupt }
