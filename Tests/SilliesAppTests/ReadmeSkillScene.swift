import AppKit
import SilliesCore
import SwiftUI

@testable import SilliesApp

/// A sample document behind the production skill wheel and companion artwork.
struct ReadmeSkillScene: View {
  private static let documentSize = CGSize(width: 984, height: 456)
  private static let documentOrigin = CGPoint(x: 108, y: 242)
  private static let wheelCenter = CGPoint(x: 845, y: 463)
  private let wheel: RadialWheelModel = {
    let model = RadialWheelModel()
    model.hoveredSkill = .participate
    return model
  }()

  let characters: [CharacterDefinition]
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(
        colors: [SilliesTheme.paper, SilliesTheme.accent.opacity(scheme == .light ? 0.16 : 0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      header.padding(.leading, 108).padding(.top, 58)
      sampleDocument
        .frame(width: Self.documentSize.width, height: Self.documentSize.height)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SilliesTheme.border))
        .shadow(color: .black.opacity(scheme == .light ? 0.10 : 0.25), radius: 30, y: 20)
        .offset(x: Self.documentOrigin.x, y: Self.documentOrigin.y)
      perchedCrew
      RadialWheelView(model: wheel)
        .position(Self.wheelCenter)
      CharacterPortrait(renderer: "cat", size: 54, registry: RendererRegistry())
        .frame(width: 70, height: 70)
        .position(Self.wheelCenter)
      footer.padding(.horizontal, 108).offset(y: 735)
    }
    .foregroundStyle(SilliesTheme.ink)
    .background(SilliesTheme.paper)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("SILLIES  /  A LITTLE COMPANY FOR YOUR MAC")
        .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.8)
        .foregroundStyle(SilliesTheme.secondary)
      Text("Small crew. Useful superpowers.")
        .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.3)
      Text("Pick up a companion. Choose what happens next.")
        .font(.system(size: 17)).foregroundStyle(SilliesTheme.secondary)
    }
  }

  private var sampleDocument: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        ForEach(["FF6057", "FEBC2E", "28C840"], id: \.self) { hex in
          Circle().fill(Color(nsColor: NSColor(hex: hex))).frame(width: 11, height: 11)
        }
        Spacer()
        Text("Design catch-up").font(.system(size: 12, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
        Spacer()
        Image(systemName: "ellipsis").foregroundStyle(SilliesTheme.secondary)
      }
      .padding(.horizontal, 20).frame(height: 48)
      Rectangle().fill(SilliesTheme.border).frame(height: 1)
      VStack(alignment: .leading, spacing: 22) {
        Text("A few things to figure out.")
          .font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-0.5)
        Text("A quieter workspace. A clearer next step.")
          .font(.system(size: 14)).foregroundStyle(SilliesTheme.secondary)
        VStack(alignment: .leading, spacing: 18) {
          agendaItem("01", "Make the first five minutes feel easy.")
          agendaItem("02", "Give the little details some personality.")
          agendaItem("03", "Leave with something worth remembering.")
        }
        .padding(.top, 6)
        Label("Sample document", systemImage: "doc.text")
          .font(.system(size: 11)).foregroundStyle(SilliesTheme.secondary).padding(.top, 16)
      }
      .padding(38)
      Spacer(minLength: 0)
    }
  }

  private func agendaItem(_ number: String, _ text: String) -> some View {
    HStack(spacing: 14) {
      Text(number).font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(SilliesTheme.accent)
      Text(text).font(.system(size: 13))
    }
  }

  private var perchedCrew: some View {
    HStack(alignment: .bottom, spacing: 40) {
      ForEach(characters.filter { ["kiko", "pogo", "bolt", "boo"].contains($0.id) }) { character in
        CharacterPortrait(renderer: character.renderer, size: 60, registry: RendererRegistry())
          .frame(width: 77, height: 77)
      }
    }
    // The production rig's feet rest 20 design points above its canvas bottom.
    .offset(x: 575, y: Self.documentOrigin.y - 77 + 12)
  }

  private var footer: some View {
    HStack {
      Text("Listen. Participate. Snap. Explain. Record.")
      Spacer()
      Label("On your Mac", systemImage: "desktopcomputer")
    }
    .font(.system(size: 12, weight: .medium)).foregroundStyle(SilliesTheme.secondary)
  }
}
