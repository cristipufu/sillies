import Darwin
import Foundation

package struct TextInferenceRequest: Codable, Sendable {
  package let configuration: TextModelPreparation
  package let generation: TextGenerationRequest
  package init(configuration: TextModelPreparation, generation: TextGenerationRequest) {
    self.configuration = configuration
    self.generation = generation
  }
}

package struct TextInferenceResponse: Codable, Sendable {
  package let text: String?
  package let failure: String?
  package init(text: String? = nil, failure: String? = nil) {
    self.text = text
    self.failure = failure
  }
}

/// Length-prefixed, bounded messages. Blocking operations belong exclusively to worker threads.
package enum TextInferenceWire {
  package static let maximumMessageBytes = 128 * 1024
  private static let headerBytes = 4
  private static let millisecondsPerSecond = 1_000.0

  package static func write<T: Encodable>(_ value: T, to handle: FileHandle, deadline: TimeInterval)
    throws
  {
    let payload = try JSONEncoder().encode(value)
    guard payload.count <= maximumMessageBytes else { throw TextModelError.invalidResponse }
    var length = UInt32(payload.count).bigEndian
    var message = withUnsafeBytes(of: &length) { Data($0) }
    message.append(payload)
    var sent = 0
    while sent < message.count {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { throw TextModelError.interrupted }
      var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLOUT), revents: 0)
      let ready = poll(
        &descriptor, 1, Int32(min(Double(Int32.max), ceil(remaining * millisecondsPerSecond))))
      if ready < 0, errno == EINTR { continue }
      guard ready > 0 else { throw TextModelError.interrupted }
      let amount = message.withUnsafeBytes {
        Darwin.write(
          handle.fileDescriptor, $0.baseAddress?.advanced(by: sent), message.count - sent)
      }
      if amount < 0, errno == EINTR || errno == EAGAIN { continue }
      guard amount > 0 else { throw TextModelError.interrupted }
      sent += amount
    }
  }

  package static func read<T: Decodable>(
    _ type: T.Type, from handle: FileHandle, deadline: TimeInterval
  ) throws -> T {
    let header = try readExactly(headerBytes, from: handle, deadline: deadline)
    let length = header.reduce(0) { ($0 << 8) | Int($1) }
    guard length > 0, length <= maximumMessageBytes else { throw TextModelError.invalidResponse }
    let data = try readExactly(length, from: handle, deadline: deadline)
    return try JSONDecoder().decode(type, from: data)
  }

  private static func readExactly(_ count: Int, from handle: FileHandle, deadline: TimeInterval)
    throws -> Data
  {
    var data = Data(count: count)
    var received = 0
    while received < count {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else {
        throw TextModelError.unavailable(
          "The local model took too long. Please try a smaller model.")
      }
      var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
      let milliseconds = Int32(min(Double(Int32.max), ceil(remaining * millisecondsPerSecond)))
      let ready = poll(&descriptor, 1, milliseconds)
      if ready < 0, errno == EINTR { continue }
      guard ready > 0 else { throw TextModelError.interrupted }
      let amount = data.withUnsafeMutableBytes {
        Darwin.read(handle.fileDescriptor, $0.baseAddress?.advanced(by: received), count - received)
      }
      if amount < 0, errno == EINTR { continue }
      guard amount > 0 else { throw TextModelError.interrupted }
      received += amount
    }
    return data
  }
}
