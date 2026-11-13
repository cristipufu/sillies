/// App composition chooses adapters. Capture, timing and native tree access do not know app types.
enum CallSpeakerProviders {
  static let make: CallSpeakerProviderFactory = { bundle in
    switch bundle {
    case "us.zoom.xos": ZoomCallSpeakerProvider()
    case "com.microsoft.teams2", "com.microsoft.teams": TeamsCallSpeakerProvider()
    case "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
      "company.thebrowser.Browser",
      "com.apple.Safari", "org.mozilla.firefox":
      MeetCallSpeakerProvider()
    default: nil
    }
  }
}
