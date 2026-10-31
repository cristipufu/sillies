import SilliesCore
import SwiftUI

struct SpeakerNamingView: View {
  let record: SessionRecord
  let rename: (SessionSpeakerIdentity, String) -> Void
  @State private var speakers: [SessionSpeakerIdentity] = []
  @State private var names: [String: String] = [:]
  var body: some View {
    if !speakers.isEmpty {
      DisclosureGroup("Name the speakers") {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "Names apply to this recording only. Review anonymous labels first; nearby speakers and overlapping speech may be misidentified."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(speakers) { speaker in
            HStack {
              Text(speaker.label).font(.caption).frame(width: 150, alignment: .leading)
              TextField(
                "Name",
                text: Binding(get: { names[speaker.id] ?? "" }, set: { names[speaker.id] = $0 })
              )
              .onSubmit { rename(speaker, names[speaker.id] ?? "") }
              Button("Save") { rename(speaker, names[speaker.id] ?? "") }
                .disabled((names[speaker.id] ?? "") == (record.speakerNames[speaker.id] ?? ""))
            }
          }
        }.padding(.top, 10)
      }
    } else {
      Color.clear.frame(height: 0)
        .task(id: record.id) {
          speakers = await SessionSpeakerWorker().speakers(in: record)
          names = record.speakerNames
        }
    }
  }
}
