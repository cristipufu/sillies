import SilliesCore

package struct ChatContextServices: Sendable {
  package let materials: (any ConversationMaterialProviding)?
  package let personalFacts: (any PersonalFactsRepository)?
  package init(
    materials: (any ConversationMaterialProviding)?, personalFacts: (any PersonalFactsRepository)?
  ) {
    self.materials = materials
    self.personalFacts = personalFacts
  }
  package static let unavailable = Self(materials: nil, personalFacts: nil)
}
