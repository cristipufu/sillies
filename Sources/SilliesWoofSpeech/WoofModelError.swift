import Foundation

enum WoofModelError: Error, Equatable {
  case invalidArchive
  case archiveLimit
  case invalidArray
  case unsupportedArrayType
  case invalidConfiguration
  case missingTensor(String)
  case invalidTensor(String)
}
