import SwiftUI

/// Shared spacing and flexible sizing for the two crew selectors.
struct CompanionGrid<Content: View>: View {
  enum Columns: Int {
    case two = 2
    case four = 4
  }

  let columns: Columns
  let spacing: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns.rawValue),
      spacing: spacing
    ) {
      content
    }
  }
}
