import AppKit
import SilliesCore
import SilliesSpeech
import SwiftUI

@testable import SilliesApp

/// Sample meeting content, with the production recording HUD and transcript view.
struct ReadmeListeningScene: View {
  private static let meetingFrame = CGRect(x: 76, y: 350, width: 640, height: 352)
  private static let companionCenter = CGPoint(x: 320, y: 320)
  private let session: AudioSessionPresentation
  private let hud: CompanionHUDModel

  init() {
    let session = AudioSessionPresentation(
      kind: .listen, sourceLabel: "Design catch-up + MacBook Pro Microphone")
    session.phase = .capturing
    session.status = "Transcribing"
    session.elapsed = 252
    session.audioLevel = 0.65
    session.languages = [.init(id: "en-US", name: "English (United States)", isInstalled: true)]
    session.selectedLanguageID = "en-US"
    session.isLoadingLanguages = false
    session.transcript = """
      [03:24] Meeting: Let’s keep the first screen simple. One clear action, with the details a click away.

      [03:38] You · microphone: I’ll put together the new layout and send it over tomorrow.

      [03:47] Meeting: Perfect. I’ll test the keyboard flow before our next catch-up.

      [04:02] You · microphone: And let’s keep all the processing on the Mac.
      """
    self.session = session
    let hud = CompanionHUDModel()
    hud.audioSession = session
    hud.state = .active(
      target: .init(windowID: 1, processID: 0, appName: "Meeting", frame: Self.meetingFrame),
      skill: .listen, startedAt: 0, statusDetail: session.statusLine, audioLevel: session.audioLevel
    )
    self.hud = hud
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(
        colors: [SilliesTheme.paper, SilliesTheme.accent.opacity(0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      header.offset(x: 76, y: 58)
      meeting
        .frame(width: Self.meetingFrame.width, height: Self.meetingFrame.height)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SilliesTheme.border))
        .shadow(color: .black.opacity(0.10), radius: 24, y: 14)
        .offset(x: Self.meetingFrame.minX, y: Self.meetingFrame.minY)
      CharacterPortrait(renderer: "cat", size: 64, registry: RendererRegistry())
        .frame(width: 82, height: 82).position(Self.companionCenter)
      CompanionHUDView(model: hud, state: hud.state).position(x: 320, y: 260)
      AudioSessionView(model: session)
        .frame(width: 560, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SilliesTheme.border))
        .shadow(color: .black.opacity(0.12), radius: 28, y: 16)
        .offset(x: 600, y: 88)
      Text("Your conversation, saved on your Mac.")
        .font(.system(size: 13, weight: .medium)).foregroundStyle(SilliesTheme.secondary)
        .offset(x: 76, y: 746)
    }
    .foregroundStyle(SilliesTheme.ink)
    .background(SilliesTheme.paper)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("SILLIES  /  LISTEN")
        .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.8)
        .foregroundStyle(SilliesTheme.secondary)
      Text("Your meeting.\nTheir full attention.")
        .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.3)
    }
  }

  private var meeting: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        ForEach(["FF6057", "FEBC2E", "28C840"], id: \.self) { hex in
          Circle().fill(Color(nsColor: NSColor(hex: hex))).frame(width: 11, height: 11)
        }
        Text("Design catch-up").font(.system(size: 12, weight: .medium))
          .padding(.leading, 18)
      }.padding(.horizontal, 20).frame(height: 48)
      Rectangle().fill(SilliesTheme.border).frame(height: 1)
      HStack(spacing: 16) {
        participant(initials: "A", name: "Alex", color: SilliesTheme.accent)
        participant(initials: "Y", name: "You", color: Color(red: 0.71, green: 0.54, blue: 0.36))
      }
      .padding(24)
      Label("Sample meeting · No live audio", systemImage: "waveform")
        .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary)
        .padding(.horizontal, 24)
      Spacer(minLength: 0)
    }
  }

  private func participant(initials: String, name: String, color: Color) -> some View {
    VStack(spacing: 14) {
      Text(initials).font(.system(size: 28, weight: .medium, design: .rounded))
        .foregroundStyle(color)
        .frame(width: 72, height: 72).background(color.opacity(0.13), in: Circle())
      Text(name).font(.system(size: 13, weight: .medium))
    }
    .frame(width: 210, height: 192)
    .background(SilliesTheme.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
  }
}
