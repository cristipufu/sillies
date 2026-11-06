import Foundation
import SilliesCore

/// Placement already resolved by the companion pass; Chat never queries window metadata during a drag.
struct ConversationCompanionAnchor {
  let companionID: String
  let position: CGPoint
  let visibleFrame: CGRect
  let edge: PerchSurface.Edge
  let window: CompanionWindowAnchor
}
