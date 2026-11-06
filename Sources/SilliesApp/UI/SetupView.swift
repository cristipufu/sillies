import SilliesCore
import SwiftUI

struct SetupView: View {
  enum Section { case profile }
  private enum Layout {
    static let pageInset: CGFloat = 28
    static let heroArtwork: CGFloat = 76
    static let heroWidth: CGFloat = 88
    static let heroHeight: CGFloat = 92
    static let haloRadius: CGFloat = 52
    static let crewArtwork: CGFloat = 64
    static let crewHeight: CGFloat = 74
    static let crewColumns = 3
    static let activityDetailHeight: CGFloat = 42
    static let stepTransitionSeconds = 0.18
  }
  @Environment(\.silliesTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let model: SetupPresentation
  let registry: RendererRegistry
  let textModels: TextModelsPresentation
  let voiceModels: VoiceModelsPresentation
  let suggestions: SetupModelSuggestions

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.horizontal, Layout.pageInset).padding(.top, 22).padding(.bottom, 20)
      steps.padding(.horizontal, Layout.pageInset).padding(.bottom, 20)
      ScrollViewReader { scroll in
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            switch model.journey.step {
            case .companion: crew
            case .activity: activities
            case .preparation:
              SetupPreparationView(
                model: model, textModels: textModels, voiceModels: voiceModels,
                suggestions: suggestions)
            }
          }.padding(.horizontal, Layout.pageInset).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: model.isProfileExpanded) { _, expanded in
          guard expanded else { return }
          withAnimation(reduceMotion ? nil : .easeInOut(duration: Layout.stepTransitionSeconds)) {
            scroll.scrollTo(Section.profile, anchor: .top)
          }
        }
      }
      Divider().overlay(theme.border)
      footer.padding(.horizontal, Layout.pageInset).padding(.vertical, 18)
    }
    .background(theme.paper)
  }

  private var header: some View {
    HStack(spacing: 18) {
      if let character = model.character {
        CharacterPortrait(
          renderer: character.renderer, size: Layout.heroArtwork, registry: registry
        )
        .frame(width: Layout.heroWidth, height: Layout.heroHeight)
        .background(
          RadialGradient(
            colors: [theme.accent.opacity(0.16), theme.accent.opacity(0.02)],
            center: .center, startRadius: 0, endRadius: Layout.haloRadius), in: Circle()
        )
        .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 7) {
        Text("Make yourself at home.")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .fixedSize(horizontal: false, vertical: true)
        Text("Start with one thing. You can add the rest later.")
          .font(.callout).foregroundStyle(theme.secondary)
        Label("All on your Mac", systemImage: "lock.shield")
          .font(.caption.weight(.medium)).foregroundStyle(theme.accent)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private var steps: some View {
    HStack(spacing: 8) {
      ForEach(Array(SetupJourney.Step.allCases.enumerated()), id: \.element) { index, step in
        Button {
          move(to: step)
        } label: {
          HStack(spacing: 7) {
            Text("\(index + 1)")
              .font(.caption.bold()).frame(width: 23, height: 23)
              .background(
                model.journey.step == step ? theme.accent : theme.border.opacity(0.5),
                in: Circle()
              )
              .foregroundStyle(model.journey.step == step ? theme.onAccent : theme.secondary)
            Text(step.title).font(.caption.weight(.semibold))
              .foregroundStyle(model.journey.step == step ? theme.ink : theme.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
        }
        .buttonStyle(.plain).accessibilityAddTraits(model.journey.step == step ? .isSelected : [])
      }
    }
  }

  private var crew: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Who’s joining you?").font(.system(.title3, design: .rounded).weight(.semibold))
      Text("Pick a first companion. Your whole crew is always in Settings.")
        .font(.callout).foregroundStyle(theme.secondary)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: Layout.crewColumns),
        spacing: 12
      ) {
        ForEach(model.characters) { character in
          Button {
            model.chooseCompanion(character.id)
          } label: {
            VStack(spacing: 4) {
              CharacterPortrait(
                renderer: character.renderer, size: Layout.crewArtwork, registry: registry
              )
              .frame(height: Layout.crewHeight)
              HStack(spacing: 5) {
                Text(character.name).font(.system(.callout, design: .rounded).weight(.semibold))
                if character.id == model.journey.companionID {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                }
              }
            }.frame(maxWidth: .infinity).padding(12)
          }.buttonStyle(SetupChoiceStyle(isSelected: character.id == model.journey.companionID))
            .accessibilityLabel(character.name)
        }
      }
    }
  }

  private var activities: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("What would you like to try?")
        .font(.system(.title3, design: .rounded).weight(.semibold))
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(SetupActivity.allCases) { activity in
          Button {
            model.chooseActivity(activity)
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Image(systemName: activity.symbol).font(.title2).foregroundStyle(theme.accent)
                  .frame(height: 24)
                Spacer()
                if activity == model.journey.activity {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                }
              }
              Text(activity.title).font(.system(.headline, design: .rounded))
              Text(activity.detail).font(.callout).foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(
                  minHeight: Layout.activityDetailHeight, alignment: .top)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(SetupChoiceStyle(isSelected: activity == model.journey.activity))
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      if model.journey.step != .companion {
        Button("Back") {
          move(to: model.journey.step == .preparation ? .activity : .companion)
        }.buttonStyle(SoftButtonStyle())
      }
      Button("Set up later", action: model.deferSetup).buttonStyle(.plain)
        .font(.callout).foregroundStyle(theme.secondary)
      Spacer(minLength: 0)
      Button(action: advance) {
        HStack(spacing: 8) {
          if model.isLaunching { ProgressView().controlSize(.small) }
          Text(primaryTitle).font(.callout.weight(.semibold))
          Image(systemName: "arrow.right")
        }.padding(.horizontal, 18).padding(.vertical, 11)
          .foregroundStyle(canAdvance ? theme.onAccent : theme.secondary)
          .background(
            canAdvance ? theme.accentFill : theme.soft, in: RoundedRectangle(cornerRadius: 11))
      }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
        .disabled(!canAdvance)
    }
  }

  private var canAdvance: Bool {
    model.character != nil && (model.journey.step != .preparation || model.canContinue)
  }

  private var primaryTitle: String {
    guard model.journey.step == .preparation else { return String(localized: "Continue") }
    switch model.journey.activity {
    case .chat: return String(localized: "Open Chat")
    case .talk: return String(localized: "Try Talk")
    case .meetings: return String(localized: "Got it")
    case .companions: return String(localized: "Meet my companion")
    }
  }
  private func advance() {
    switch model.journey.step {
    case .companion: move(to: .activity)
    case .activity: move(to: .preparation)
    case .preparation: model.complete()
    }
  }
  private func move(to step: SetupJourney.Step) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: Layout.stepTransitionSeconds)) {
      model.move(to: step)
    }
  }
}
