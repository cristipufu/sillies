import AVFoundation
import AppKit
import Observation
import SilliesCore
import SwiftUI

@MainActor @Observable
final class RecordingPlaybackModel {
  var duration: Double = 0
  var position: Double = 0
  var isPlaying = false
  var error: String?
  @ObservationIgnored private var player: AVPlayer?
  @ObservationIgnored private var observer: Any?
  @ObservationIgnored private var endObserver: NSObjectProtocol?
  private static let progressInterval = CMTime(seconds: 0.5, preferredTimescale: 600)

  func prepare(_ url: URL) async {
    stop()
    do {
      let asset = AVURLAsset(url: url)
      let duration = try await asset.load(.duration).seconds
      guard !Task.isCancelled, duration.isFinite, duration > 0 else { return }
      self.duration = duration
      let item = AVPlayerItem(asset: asset)
      let player = AVPlayer(playerItem: item)
      self.player = player
      observer = player.addPeriodicTimeObserver(forInterval: Self.progressInterval, queue: .main) {
        [weak self] time in
        MainActor.assumeIsolated { self?.position = max(0, time.seconds) }
      }
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.isPlaying = false }
      }
    } catch { self.error = "Could not open recording: \(error.localizedDescription)" }
  }

  func togglePlayback() {
    guard let player else { return }
    if isPlaying {
      player.pause()
    } else {
      if position >= duration { seek(to: 0) }
      player.play()
    }
    isPlaying.toggle()
  }

  func seek(to seconds: Double) {
    position = seconds
    player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
  }

  func stop() {
    player?.pause()
    if let observer { player?.removeTimeObserver(observer) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    observer = nil
    endObserver = nil
    player = nil
    isPlaying = false
  }
}

struct RecordingPlaybackView: View {
  let url: URL
  @State private var model = RecordingPlaybackModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("RECORDING", systemImage: "waveform").font(.caption.weight(.semibold))
        Spacer()
        Button("Show audio file") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
      HStack(spacing: 12) {
        Button(action: model.togglePlayback) {
          Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title)
        }.buttonStyle(.plain).disabled(model.duration <= 0)
          .accessibilityLabel(model.isPlaying ? "Pause recording" : "Play recording")
        Slider(
          value: Binding(get: { model.position }, set: { model.seek(to: $0) }),
          in: 0...max(1, model.duration)
        )
        .accessibilityLabel("Playback position")
        Text(
          "\(SessionRecord.formatDuration(model.position)) / \(SessionRecord.formatDuration(model.duration))"
        )
        .font(.caption).monospacedDigit()
      }
    }.padding(16).background(SilliesTheme.soft, in: RoundedRectangle(cornerRadius: 14))
      .task(id: url) { await model.prepare(url) }.onDisappear { model.stop() }
  }
}
