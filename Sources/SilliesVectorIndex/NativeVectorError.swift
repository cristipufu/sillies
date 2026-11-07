import Foundation

struct NativeVectorError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }

  init(messageBuffer: [CChar]) {
    message = String(
      decoding: messageBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
