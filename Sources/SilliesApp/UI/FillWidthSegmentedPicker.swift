import AppKit
import SwiftUI

/// Native segments share the full width proposed by their SwiftUI layout.
struct FillWidthSegmentedPicker<Selection: Equatable>: NSViewRepresentable {
  @Environment(\.silliesTheme) private var theme

  struct Choice {
    let value: Selection
    let title: String
  }

  @Binding var selection: Selection
  let choices: [Choice]
  let label: String

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection, choices: choices)
  }

  func makeNSView(context: Context) -> ThemedSegmentedControl {
    let control = ThemedSegmentedControl(theme: theme)
    control.trackingMode = .selectOne
    control.target = context.coordinator
    control.action = #selector(Coordinator.selectionChanged(_:))
    control.segmentStyle = .rounded
    control.segmentDistribution = .fillEqually
    control.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return control
  }

  func updateNSView(_ control: ThemedSegmentedControl, context: Context) {
    context.coordinator.update(selection: $selection, choices: choices)
    control.applyTheme(theme)
    control.isEnabled = context.environment.isEnabled
    control.setAccessibilityLabel(label)
    if control.segmentCount != choices.count { control.segmentCount = choices.count }
    for (index, choice) in choices.enumerated() {
      if control.label(forSegment: index) != choice.title {
        control.setLabel(choice.title, forSegment: index)
      }
      control.setSelected(choice.value == selection, forSegment: index)
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedSegmentedControl, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, width.isFinite else { return nil }
    return CGSize(width: max(0, width), height: nsView.intrinsicContentSize.height)
  }

  @MainActor final class Coordinator: NSObject {
    private var selection: Binding<Selection>
    private var choices: [Choice]

    init(selection: Binding<Selection>, choices: [Choice]) {
      self.selection = selection
      self.choices = choices
    }

    func update(selection: Binding<Selection>, choices: [Choice]) {
      self.selection = selection
      self.choices = choices
    }

    @objc func selectionChanged(_ sender: NSSegmentedControl) {
      guard sender.isEnabled, choices.indices.contains(sender.selectedSegment) else { return }
      let value = choices[sender.selectedSegment].value
      if value != selection.wrappedValue { selection.wrappedValue = value }
    }
  }
}
