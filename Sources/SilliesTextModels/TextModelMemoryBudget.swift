import Foundation

/// Admission uses verified weight sizes; larger catalogs must not silently inherit a small-model cap.
package enum TextModelMemoryBudget {
  package static let gibibyte = 1_073_741_824
  private static let maximumAllocation = 32 * gibibyte
  private static let minimumWorkspace = 2 * gibibyte

  package static func maximumAllocation(physicalMemory: UInt64) -> Int {
    // Leave at least one third of physical memory for macOS, capture, voices, and other apps.
    Int(min(UInt64(maximumAllocation), physicalMemory / 3 * 2))
  }

  package static func allocation(weightBytes: Int64, physicalMemory: UInt64) throws -> Int {
    let limit = maximumAllocation(physicalMemory: physicalMemory)
    guard weightBytes > 0, let weights = Int(exactly: weightBytes), weights <= limit else {
      throw TextModelError.unavailable("This text model is too large for this Mac’s memory budget.")
    }
    let workspace = max(minimumWorkspace, weights / 4)
    guard weights <= limit - workspace else {
      throw TextModelError.unavailable("There is not enough memory headroom for this text model.")
    }
    return weights + workspace
  }
}
