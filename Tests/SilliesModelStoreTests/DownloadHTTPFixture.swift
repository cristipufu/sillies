import Foundation
import Network
import Synchronization

/// A small, throttled loopback response exercises URLSession itself without model downloads.
final class DownloadHTTPFixture: Sendable {
  static let chunkBytes = 65_536
  static let chunkDelay: TimeInterval = 0.025
  let data = Data(repeating: 42, count: chunkBytes * 16)
  private let queue = DispatchQueue(label: "sillies.download-fixture")
  private let listener: NWListener
  private let connections = Mutex<[NWConnection]>([])

  init() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
  }

  func start() async throws -> URL {
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else {
        connection.cancel()
        return
      }
      self.connections.withLock { $0.append(connection) }
      connection.start(queue: self.queue)
      self.readRequest(connection, previous: Data())
    }
    let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
      let completed = Mutex(false)
      listener.stateUpdateHandler = { [listener] state in
        let result: Result<NWEndpoint.Port, Error>
        switch state {
        case .ready:
          guard let port = listener.port else { return }
          result = .success(port)
        case .failed(let error): result = .failure(error)
        default: return
        }
        if completed.withLock({ previous in
          guard !previous else { return false }
          previous = true
          return true
        }) {
          continuation.resume(with: result)
        }
      }
      listener.start(queue: queue)
    }
    guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/weights.bin") else {
      throw URLError(.badURL)
    }
    return url
  }

  func stop() {
    listener.cancel()
    for connection in connections.withLock({ $0 }) { connection.cancel() }
  }

  private func readRequest(_ connection: NWConnection, previous: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) {
      [weak self] bytes, _, done, error in
      guard let self, let bytes, error == nil else {
        connection.cancel()
        return
      }
      let request = previous + bytes
      guard request.count <= 8_192 else {
        connection.cancel()
        return
      }
      guard let header = String(data: request, encoding: .utf8), header.contains("\r\n\r\n") else {
        if !done { self.readRequest(connection, previous: request) }
        return
      }
      self.respond(connection, header: header)
    }
  }

  private func respond(_ connection: NWConnection, header: String) {
    let range = header.components(separatedBy: "\r\n").first {
      $0.lowercased().hasPrefix("range: bytes=")
    }
    let start =
      range.flatMap { Int($0.dropFirst("range: bytes=".count).split(separator: "-")[0]) } ?? 0
    let offset = min(data.count, max(0, start))
    let status = offset > 0 ? "206 Partial Content" : "200 OK"
    let contentRange =
      offset > 0 ? "Content-Range: bytes \(offset)-\(data.count - 1)/\(data.count)\r\n" : ""
    let response =
      "HTTP/1.1 \(status)\r\nContent-Length: \(data.count - offset)\r\nAccept-Ranges: bytes\r\nETag: \"fixture-v1\"\r\nLast-Modified: Wed, 21 Oct 2015 07:28:00 GMT\r\n\(contentRange)Connection: close\r\n\r\n"
    connection.send(
      content: Data(response.utf8),
      completion: .contentProcessed { [weak self] error in
        guard error == nil else {
          connection.cancel()
          return
        }
        self?.sendBody(connection, offset: offset)
      })
  }

  private func sendBody(_ connection: NWConnection, offset: Int) {
    guard offset < data.count else {
      connection.cancel()
      return
    }
    let end = min(data.count, offset + Self.chunkBytes)
    connection.send(
      content: data.subdata(in: offset..<end),
      completion: .contentProcessed { [weak self] error in
        guard let self, error == nil else {
          connection.cancel()
          return
        }
        self.queue.asyncAfter(deadline: .now() + Self.chunkDelay) { [weak self] in
          self?.sendBody(connection, offset: end)
        }
      })
  }
}
