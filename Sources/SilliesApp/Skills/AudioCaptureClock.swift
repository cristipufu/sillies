import CoreMedia
import Foundation

/// Shared monotonic timebase for microphone, ScreenCaptureKit, and session elapsed time.
enum AudioCaptureClock {
  static var now: TimeInterval { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}
