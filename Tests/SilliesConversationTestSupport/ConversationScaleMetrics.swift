import Darwin
import Foundation

package enum ConversationScaleMetrics {
  package static func residentBytes() throws -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else { throw CocoaError(.coderInvalidValue) }
    return info.resident_size
  }

  package static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }

  package static func percentile(_ values: [Double], fraction: Double) -> Double {
    let sorted = values.sorted()
    return sorted[max(0, Int((Double(sorted.count) * fraction).rounded(.up)) - 1)]
  }

  package static func pulseMainActor() async -> Double {
    var maximumDelay = 0.0
    while !Task.isCancelled {
      let started = ContinuousClock.now
      await MainActor.run {}
      maximumDelay = max(maximumDelay, seconds(started.duration(to: .now)))
      do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
    }
    return maximumDelay
  }
}
