/// A zero timestamp must not send the native decoder through the same bounded audio again.
enum WhisperSeekProgress {
  private static let terminalOffset = Int.max

  static func advance(from current: Int, proposed: Int, sampleCount: Int) -> Int {
    guard current >= 0, sampleCount > 0 else { return terminalOffset }
    guard proposed <= current else { return proposed }
    let (end, overflow) = current.addingReportingOverflow(sampleCount)
    return overflow ? terminalOffset : end
  }
}
