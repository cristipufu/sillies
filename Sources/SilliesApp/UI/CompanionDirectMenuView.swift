import SilliesCore
import SwiftUI

struct CompanionDirectMenuView: View {
  let layout: CompanionActionMenuLayout
  let perform: (CompanionDirectAction) -> Void
  @State private var hovered: CompanionDirectAction?
  var body: some View {
    ZStack {
      RadialMenuOrbit(radius: layout.radius).position(local(layout.anchor))
      ForEach(Array(zip(CompanionDirectAction.allCases, layout.centers)), id: \.0.id) {
        action, center in
        Button {
          perform(action)
        } label: {
          RadialActionBubble(
            title: action.title, symbol: action.symbol,
            isSelected: hovered == action, titleWidth: action.titleWidth)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? action : nil }
        .position(local(center))
      }
    }
    .frame(width: layout.frame.width, height: layout.frame.height)
  }
  private func local(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x - layout.frame.minX, y: layout.frame.maxY - point.y)
  }
}
