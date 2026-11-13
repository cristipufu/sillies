import CoreAudio
import Foundation

/// Checks native sizes before allocation or conversion. Only fixed-width values leave this boundary.
enum CoreAudioProperties {
  struct Property {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    var scope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
    var address: AudioObjectPropertyAddress {
      .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
  }
  static let maximumObjects = 1_024
  private static let maximumStringBytes = 1_024

  static func objects(_ property: Property, limit: Int = maximumObjects) throws -> [AudioObjectID] {
    var address = property.address
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(property.object, &address, 0, nil, &size))
    let stride = MemoryLayout<AudioObjectID>.stride
    guard limit >= 0, Int(size) % stride == 0, Int(size) / stride <= limit else {
      throw CoreAudioCaptureError.unsupported
    }
    let count = Int(size) / stride
    if count == 0 { return [] }
    var values = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
    let capacity = size
    let status = try values.withUnsafeMutableBytes { bytes in
      guard let base = bytes.baseAddress else { throw CoreAudioCaptureError.unsupported }
      return AudioObjectGetPropertyData(property.object, &address, 0, nil, &size, base)
    }
    try check(status)
    guard size <= capacity, Int(size) % stride == 0 else { throw CoreAudioCaptureError.unsupported }
    return Array(values.prefix(Int(size) / stride))
  }
  static func integer(_ property: Property) throws -> UInt32 {
    var address = property.address
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    try check(AudioObjectGetPropertyData(property.object, &address, 0, nil, &size, &value))
    guard size == MemoryLayout<UInt32>.size else { throw CoreAudioCaptureError.unsupported }
    return value
  }
  static func sampleRate(_ property: Property) throws -> Double {
    var address = property.address
    var size = UInt32(MemoryLayout<Double>.size)
    var value: Double = 0
    try check(AudioObjectGetPropertyData(property.object, &address, 0, nil, &size, &value))
    guard size == MemoryLayout<Double>.size, value.isFinite,
      (CoreAudioPacketEmitter.minimumSampleRate...CoreAudioPacketEmitter.maximumSampleRate)
        .contains(value)
    else { throw CoreAudioCaptureError.unsupported }
    return value
  }
  static func string(_ property: Property) throws -> String? {
    var address = property.address
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    try check(AudioObjectGetPropertyData(property.object, &address, 0, nil, &size, &value))
    let result = value?.takeRetainedValue()
    guard size == MemoryLayout<Unmanaged<CFString>?>.size else {
      throw CoreAudioCaptureError.unsupported
    }
    guard let result else { return nil }
    guard CFGetTypeID(result) == CFStringGetTypeID() else {
      throw CoreAudioCaptureError.unsupported
    }
    let string = result as String
    guard string.utf8.count <= maximumStringBytes else { throw CoreAudioCaptureError.unsupported }
    return string
  }
  static func format(_ property: Property) throws -> AudioStreamBasicDescription {
    var address = property.address
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var value = AudioStreamBasicDescription()
    try check(AudioObjectGetPropertyData(property.object, &address, 0, nil, &size, &value))
    guard size == MemoryLayout<AudioStreamBasicDescription>.size else {
      throw CoreAudioCaptureError.unsupported
    }
    return value
  }
  private static func check(_ status: OSStatus) throws {
    if status != noErr { throw CoreAudioCaptureError.native(.properties, status) }
  }
}
