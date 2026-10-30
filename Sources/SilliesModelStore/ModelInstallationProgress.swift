import Foundation

package struct ModelInstallationProgress: Sendable {
  package enum Phase: Sendable { case downloading, verifying }
  package let phase: Phase
  package let completedBytes: Int64
  package let totalBytes: Int64
}
