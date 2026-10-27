import SilliesCore
import Testing

@Test func meetingFramesPairCaptureTimesDespiteReversedCallbackOrder() throws {
  var timeline = MeetingAudioTimeline()
  let microphone = [Float](repeating: 0.2, count: 2_080)
  let reference = [Float](repeating: 0.7, count: 2_080)
  try timeline.append(microphone, source: .microphone, at: 100)
  try timeline.append(reference, source: .meeting, at: 100)
  let ready = timeline.nextReadyFrame()
  let frame = try #require(ready)
  #expect(frame.startTime == 100)
  #expect(frame.microphone == Array(microphone.prefix(160)))
  #expect(frame.meeting == Array(reference.prefix(160)))
  let pending = timeline.nextReadyFrame()
  #expect(pending == nil)
}

@Test func meetingTimelinePadsGapsAndFlushesEveryFinalSample() throws {
  var timeline = MeetingAudioTimeline()
  try timeline.append([Float](repeating: 0.5, count: 321), source: .microphone, at: 10)
  try timeline.append([Float](repeating: 0.3, count: 160), source: .meeting, at: 10.01)
  var frames: [MeetingAudioTimeline.Frame] = []
  while let frame = timeline.nextFinalFrame() { frames.append(frame) }
  #expect(frames.map(\.validSamples) == [160, 160, 1])
  #expect(frames[0].meeting.allSatisfy { $0 == 0 })
  #expect(frames[1].meeting.allSatisfy { $0 == 0.3 })
  #expect(frames[2].microphone[0] == 0.5)
}

@Test func meetingTimelineRejectsUnboundedClockJumps() throws {
  var timeline = MeetingAudioTimeline()
  try timeline.append([0.1], source: .microphone, at: 10)
  #expect(throws: MeetingAudioTimeline.Failure.self) {
    try timeline.append([0.1], source: .meeting, at: 100)
  }
  #expect(throws: MeetingAudioTimeline.Failure.self) {
    try timeline.append([0.1], source: .meeting, at: .nan)
  }
}
