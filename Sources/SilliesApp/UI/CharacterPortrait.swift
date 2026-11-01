import SwiftUI

struct CharacterPortrait: NSViewRepresentable {
  let renderer: String
  let size: Double
  let registry: RendererRegistry

  func makeNSView(context: Context) -> CompanionView {
    let rig = registry.make(renderer) ?? CharacterRig()
    return CompanionView.makePortrait(rig: rig, size: size)
  }

  func updateNSView(_ view: CompanionView, context: Context) { view.resize(to: size) }
}
