import CoreGraphics
import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

@Test func callSpeakerVisualInterpretationBelongsToTheSelectedProvider() async throws {
  #expect(ZoomCallSpeakerProvider().visualInterpreter != nil)
  #expect(TeamsCallSpeakerProvider().visualInterpreter == nil)
  #expect(MeetCallSpeakerProvider().visualInterpreter == nil)
  let fixture = try SpeakerBorderFixture()
  let blue = CallSpeakerBorder.Color(red: 72, green: 92, blue: 221)
  let image = try fixture.image(contents: .borders(["Bob"]), color: blue)
  #expect(ZoomSpeakerHighlight().speakers(in: image, layout: fixture.layout)?.isEmpty == true)
  let request = CallSpeakerVisualRequest(
    source: fixture.request.source, layout: fixture.layout,
    interpreter: FixtureOutlineInterpreter(style: .init(color: blue, tolerance: 24)))
  let capture = ControlledSpeakerImageCapture()
  let reader = CallSpeakerHighlightReader(capture: capture)
  let pending = Task { await reader.read(request) }
  var starts = capture.starts.makeAsyncIterator()
  _ = await starts.next()
  await capture.complete(image)
  #expect(await pending.value?.speaking.map(\.rawValue) == ["Bob"])
  await reader.stop()
}

@Test func callSpeakerVisualNamesRequireOneUnmutedBorderAndPreserveTranscriptWords() throws {
  let fixture = try SpeakerBorderFixture()
  let alice = try fixture.names(highlights: ["Alice"])
  let bob = try fixture.names(highlights: ["Bob"])
  #expect(alice.map(\.rawValue) == ["Alice"])
  #expect(bob.map(\.rawValue) == ["Bob"])
  #expect(try fixture.names(highlights: ["Alice", "Bob"]).isEmpty)
  #expect(try fixture.names(highlights: []).isEmpty)
  let filled = try fixture.image(contents: .greenVideo)
  #expect(ZoomSpeakerHighlight().speakers(in: filled, layout: fixture.layout)?.isEmpty == true)
  let muted = try SpeakerBorderFixture(audio: .muted)
  #expect(try muted.names(highlights: ["Alice"]).isEmpty)

  var timeline = CallSpeakerTimeline()
  for step in 0...20 {
    let time = Double(step) / 2
    timeline.append(
      .init(
        source: fixture.request.source, capturedAt: time, availability: .available,
        speaking: time < 5 ? alice : bob, participants: fixture.layout.tiles.map(\.name)),
      at: time)
  }
  var transcript = TranscriptTimeline()
  transcript.receive(.init(source: "Meeting", range: 1..<2, text: "First words.", isFinal: true))
  transcript.receive(.init(source: "Meeting", range: 4..<6, text: "Changing turns.", isFinal: true))
  transcript.receive(.init(source: "Meeting", range: 7..<8, text: "Next words.", isFinal: true))
  let original = transcript.originalText
  transcript.attributeCallSpeakers(using: timeline, source: "Meeting")
  #expect(transcript.text.contains("Meeting · Alice: First words."))
  #expect(transcript.text.contains("Meeting: Changing turns."))
  #expect(transcript.text.contains("Meeting · Bob: Next words."))
  #expect(transcript.originalText == original)
}

@Test func callSpeakerVisualCaptureRejectsWrongDimensionsAndMissingImages() async throws {
  let fixture = try SpeakerBorderFixture()
  let image = try fixture.image(contents: .borders(["Alice"]))
  let cropped = try #require(
    image.cropping(to: CGRect(x: 0, y: 0, width: image.width - 1, height: image.height)))
  #expect(ZoomSpeakerHighlight().speakers(in: cropped, layout: fixture.layout) == nil)
  let capture = ControlledSpeakerImageCapture()
  let reader = CallSpeakerHighlightReader(capture: capture)
  let pending = Task { await reader.read(fixture.request) }
  var starts = capture.starts.makeAsyncIterator()
  _ = await starts.next()
  await capture.complete(nil)
  #expect(await pending.value == nil)
  await reader.stop()
}

@Test func callSpeakerVisualCancellationKeepsNativeAdmissionBoundedAndStopRejectsLateImages()
  async throws
{
  let fixture = try SpeakerBorderFixture()
  let capture = ControlledSpeakerImageCapture()
  let reader = CallSpeakerHighlightReader(capture: capture)
  let pending = Task { await reader.read(fixture.request) }
  var starts = capture.starts.makeAsyncIterator()
  _ = await starts.next()
  pending.cancel()
  #expect(await reader.read(fixture.request) == nil)
  #expect(await capture.readCount == 1)
  await reader.stop()
  await reader.stop()
  #expect(await capture.stopCount == 1)
  await capture.complete(try fixture.image(contents: .borders(["Alice"])))
  #expect(await pending.value == nil)
  #expect(await reader.read(fixture.request) == nil)
  #expect(await capture.readCount == 1)
}

private struct SpeakerBorderFixture {
  enum Contents {
    case borders(Set<String>)
    case greenVideo
  }
  private static let bytesPerPixel = 4
  private static let borderWidth: CGFloat = 3
  let layout: CallSpeakerVisualLayout
  var request: CallSpeakerVisualRequest {
    .init(
      source: .init(processID: 42, windowID: 7), layout: layout, interpreter: ZoomSpeakerHighlight()
    )
  }

  init(audio: CallSpeakerTile.Audio = .unmuted) throws {
    let alice = try #require(CallSpeakerName(rawValue: "Alice"))
    let bob = try #require(CallSpeakerName(rawValue: "Bob"))
    layout = try #require(
      CallSpeakerVisualLayout(
        windowFrame: CGRect(x: 0, y: 0, width: 600, height: 400),
        tiles: [
          .init(name: alice, frame: CGRect(x: 20, y: 30, width: 160, height: 90), audio: audio),
          .init(name: bob, frame: CGRect(x: 20, y: 130, width: 160, height: 90), audio: audio),
        ]))
  }

  func names(highlights: Set<String>) throws -> [CallSpeakerName] {
    try #require(
      ZoomSpeakerHighlight().speakers(in: image(contents: .borders(highlights)), layout: layout))
  }

  func image(
    contents: Contents, color: CallSpeakerBorder.Color = .init(red: 72, green: 221, blue: 92)
  ) throws -> CGImage {
    let width = Int(layout.crop.width)
    let height = Int(layout.crop.height)
    var pixels = [UInt8](repeating: 45, count: width * height * Self.bytesPerPixel)
    for y in 0..<height {
      for x in 0..<width {
        let point = CGPoint(x: x, y: y)
        let green: Bool
        switch contents {
        case .greenVideo: green = true
        case .borders(let names):
          green = layout.tiles.contains {
            let frame = layout.imageFrame(for: $0)
            return names.contains($0.name.rawValue) && frame.contains(point)
              && !frame.insetBy(dx: Self.borderWidth, dy: Self.borderWidth).contains(point)
          }
        }
        let offset = (y * width + x) * Self.bytesPerPixel
        if green {
          pixels[offset] = color.red
          pixels[offset + 1] = color.green
          pixels[offset + 2] = color.blue
        }
        pixels[offset + 3] = 255
      }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    return try #require(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * Self.bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
          .union(.byteOrder32Big),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }
}

private struct FixtureOutlineInterpreter: CallSpeakerVisualInterpreting {
  let style: CallSpeakerBorder.Style
  func speakers(in image: CGImage, layout: CallSpeakerVisualLayout) -> [CallSpeakerName]? {
    CallSpeakerBorderImage.speakers(in: image, layout: layout, style: style)
  }
}

private actor ControlledSpeakerImageCapture: CallSpeakerImageCapturing {
  nonisolated let starts: AsyncStream<Void>
  private let started: AsyncStream<Void>.Continuation
  private var completion: CheckedContinuation<CGImage?, Never>?
  private(set) var readCount = 0
  private(set) var stopCount = 0

  init() { (starts, started) = AsyncStream<Void>.makeStream() }
  func capture(_ request: CallSpeakerVisualRequest) async -> CGImage? {
    readCount += 1
    return await withCheckedContinuation {
      completion = $0
      started.yield(())
    }
  }
  func complete(_ image: CGImage?) {
    completion?.resume(returning: image)
    completion = nil
  }
  func stop() { stopCount += 1 }
}
