import Darwin
import Foundation

/// CLI signals request cooperative cancellation; the caller owns cleanup before exiting.
final class BenchmarkInterrupts {
  private struct Handler {
    let number: Int32
    var previous: sigaction
    let source: any DispatchSourceSignal
  }
  private var handlers: [Handler] = []

  init(receive: @escaping @Sendable (Int32) -> Void) throws {
    do {
      for number in [SIGINT, SIGTERM] {
        var ignored = sigaction()
        ignored.__sigaction_u.__sa_handler = SIG_IGN
        sigemptyset(&ignored.sa_mask)
        var previous = sigaction()
        guard sigaction(number, &ignored, &previous) == 0 else {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .utility))
        source.setEventHandler { receive(number) }
        handlers.append(.init(number: number, previous: previous, source: source))
        source.resume()
      }
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    for var handler in handlers {
      handler.source.cancel()
      if sigaction(handler.number, &handler.previous, nil) != 0 {
        fputs("Could not restore benchmark signal handler: \(errno)\n", stderr)
      }
    }
    handlers.removeAll()
  }

  deinit { stop() }
}
