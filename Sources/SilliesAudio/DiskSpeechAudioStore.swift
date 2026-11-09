import Foundation
import SilliesSpeech
import Synchronization

/// Private PCM pages preserve uncommitted recognition audio independently of inference speed.
/// Capture appends on its worker; recognition reads on its worker. The mutex owns every file handle.
package final class DiskSpeechAudioStore: SpeechAudioBackingStore, Sendable {
  private struct Page: Sendable {
    let url: URL
    let start: Int64
    var samples = 0
    var end: Int64 { start + Int64(samples) }
  }
  private struct State {
    var pages: [Page] = []
    var writer: FileHandle?
    var end: Int64 = 0
    var retired: Int64 = 0
    var closed = false
    var created = false
  }
  private static let pageSamples = 4 * 16_000
  private static let maximumPendingBytes = 64 * 1_024 * 1_024
  private let maximumPendingSamples: Int
  private let directory: URL
  private let state = Mutex(State())

  package convenience init(directory: URL) {
    self.init(directory: directory, maximumPendingBytes: Self.maximumPendingBytes)
  }
  init(directory: URL, maximumPendingBytes: Int) {
    self.directory = directory.appendingPathComponent(".\(UUID().uuidString).speech-backlog")
    maximumPendingSamples = max(0, maximumPendingBytes / MemoryLayout<Float>.size)
  }
  package var endSample: Int64 { state.withLock { $0.end } }

  package func append(_ samples: [Float]) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try state.withLock { state in
      guard !state.closed else { throw CancellationError() }
      guard !samples.isEmpty else { return }
      guard samples.count <= maximumPendingSamples,
        state.end - (state.pages.first?.start ?? state.end)
          <= Int64(maximumPendingSamples - samples.count),
        state.end <= Int64.max - Int64(samples.count)
      else { throw SpeechError.overloaded }
      if !state.created {
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        state.created = true
      }
      var offset = 0
      while offset < samples.count {
        if state.pages.last?.samples == Self.pageSamples || state.writer == nil {
          try openPage(&state)
        }
        guard let writer = state.writer, !state.pages.isEmpty else {
          throw CocoaError(.fileWriteUnknown)
        }
        let index = state.pages.count - 1
        let count = min(Self.pageSamples - state.pages[index].samples, samples.count - offset)
        let data = samples.withUnsafeBytes { bytes in
          Data(
            bytes[
              (offset * MemoryLayout<Float>.size)..<((offset + count) * MemoryLayout<Float>.size)])
        }
        try writer.write(contentsOf: data)
        state.pages[index].samples += count
        state.end += Int64(count)
        offset += count
      }
    }
  }

  package func read(from sample: Int64, maximumSamples: Int) throws -> [Float] {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return try state.withLock { state in
      guard !state.closed else { throw CancellationError() }
      guard sample >= state.retired, sample <= state.end, maximumSamples > 0 else { return [] }
      guard let page = state.pages.first(where: { $0.start <= sample && sample < $0.end }) else {
        return []
      }
      let count = min(maximumSamples, Int(page.end - sample))
      let reader = try FileHandle(forReadingFrom: page.url)
      do {
        try reader.seek(toOffset: UInt64(sample - page.start) * UInt64(MemoryLayout<Float>.size))
        let data = try reader.read(upToCount: count * MemoryLayout<Float>.size) ?? Data()
        try reader.close()
        guard data.count == count * MemoryLayout<Float>.size else {
          throw CocoaError(.fileReadCorruptFile)
        }
        return data.withUnsafeBytes { bytes in
          (0..<count).map {
            bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self)
          }
        }
      } catch {
        do { try reader.close() } catch {
          fputs("Speech backlog reader could not close.\n", stderr)
        }
        throw error
      }
    }
  }

  package func retire(before sample: Int64) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try state.withLock { state in
      state.retired = min(state.end, max(state.retired, sample))
      while let page = state.pages.first, page.end <= state.retired {
        if state.pages.count == 1 {
          try state.writer?.close()
          state.writer = nil
        }
        try FileManager.default.removeItem(at: page.url)
        state.pages.removeFirst()
      }
    }
  }

  package func close() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try state.withLock { state in
      state.closed = true
      try state.writer?.close()
      state.writer = nil
      if state.created {
        try FileManager.default.removeItem(at: directory)
        state.created = false
      }
      state.pages.removeAll()
    }
  }

  private func openPage(_ state: inout State) throws {
    try state.writer?.close()
    state.writer = nil
    let page = Page(url: directory.appendingPathComponent("\(state.end).pcm"), start: state.end)
    guard
      FileManager.default.createFile(
        atPath: page.url.path, contents: nil,
        attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }
    state.writer = try FileHandle(forWritingTo: page.url)
    state.pages.append(page)
  }
}
