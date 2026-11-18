import CoreGraphics
import SilliesCore

/// The tile outline observed in the native client's participant strip, independent of video content.
struct ZoomSpeakerHighlight: CallSpeakerVisualInterpreting {
  private static let style = CallSpeakerBorder.Style(
    color: .init(red: 72, green: 221, blue: 92), tolerance: 24)

  func speakers(in image: CGImage, layout: CallSpeakerVisualLayout) -> [CallSpeakerName]? {
    CallSpeakerBorderImage.speakers(in: image, layout: layout, style: Self.style)
  }
}
