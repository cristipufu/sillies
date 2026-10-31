import SwiftUI

struct PersonalDictionarySettings: View {
  let model: VocabularyPreferences
  @State private var phrase = ""
  @State private var heardAs = ""
  var body: some View {
    DisclosureGroup("Personal dictionary · \(model.entries.count) entries") {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          "Help recognition with names, jargon, and technical terms. Add a “heard as” spelling to correct a repeated mistake."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        TextField("Preferred spelling, e.g. Ștefănescu", text: $phrase).textFieldStyle(
          .roundedBorder)
        TextField("Often heard as (optional)", text: $heardAs).textFieldStyle(.roundedBorder)
        Button("Add word or phrase", systemImage: "plus") {
          model.add(phrase: phrase, heardAs: heardAs)
          if model.error == nil {
            phrase = ""
            heardAs = ""
          }
        }.buttonStyle(.borderedProminent)
          .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
        ForEach(model.entries) { entry in
          HStack {
            Text(entry.heardAs.isEmpty ? entry.phrase : "\(entry.heardAs) → \(entry.phrase)")
            Spacer()
            Button {
              model.remove(entry.id)
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain).accessibilityLabel("Remove \(entry.phrase)")
          }
        }
      }.padding(.top, 12)
    }.font(.callout)
  }
}
