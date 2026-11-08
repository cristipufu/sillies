enum VibeVoiceError: Error {
  case unsupportedConfiguration
  case invalidTensor(String)
  case invalidVoice
}
