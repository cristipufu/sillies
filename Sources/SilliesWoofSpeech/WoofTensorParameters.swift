import Foundation

struct WoofTensorReference: Decodable {
  let name: String
  enum CodingKeys: String, CodingKey { case name = "@" }
}

struct WoofLinearParameter: Decodable {
  let quantized: WoofTensorReference?
  let scale: WoofTensorReference?
  let weight: WoofTensorReference?
  let bias: WoofTensorReference?

  enum CodingKeys: String, CodingKey {
    case quantized = "q"
    case scale = "s"
    case weight = "w"
    case bias = "b"
  }
}

enum WoofTensorParameter: Decodable {
  struct Grouped: Decodable {
    let quantized: WoofTensorReference
    let scale: WoofTensorReference
    let shape: [Int]
    let axis: Int
    let groupSize: Int

    enum CodingKeys: String, CodingKey {
      case quantized = "q8"
      case scale = "s"
      case shape, axis
      case groupSize = "g"
    }
  }

  case array(WoofTensorReference)
  case grouped(Grouped)

  private enum CodingKeys: String, CodingKey { case reference = "@" }

  init(from decoder: any Swift.Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    if fields.contains(.reference) {
      self = .array(try WoofTensorReference(from: decoder))
    } else {
      self = .grouped(try Grouped(from: decoder))
    }
  }
}

enum WoofDecoderOperation: Decodable {
  struct Convolution: Decodable {
    let weight: WoofTensorParameter
    let bias: WoofTensorReference
    let stride: Int?

    enum CodingKeys: String, CodingKey {
      case weight = "w"
      case bias = "b"
      case stride
    }
  }

  case convolution(Convolution)
  case upsample(Convolution)
  case residual(Convolution, Convolution)
  case activation

  init(from decoder: any Swift.Decoder) throws {
    var pair = try decoder.unkeyedContainer()
    switch try pair.decode(String.self) {
    case "conv": self = .convolution(try pair.decode(Convolution.self))
    case "convt": self = .upsample(try pair.decode(Convolution.self))
    case "res":
      let layers = try pair.decode([Convolution].self)
      guard layers.count == 2 else { throw WoofModelError.invalidConfiguration }
      self = .residual(layers[0], layers[1])
    case "elu":
      guard try pair.decodeNil() else { throw WoofModelError.invalidConfiguration }
      self = .activation
    default: throw WoofModelError.invalidConfiguration
    }
    guard pair.isAtEnd else { throw WoofModelError.invalidConfiguration }
  }
}

/// Decode positional storage once; tensor consumers use named parameters.
struct WoofSpeechLayerParameters: Decodable {
  let queryKeyValue: WoofLinearParameter
  let attentionOutput: WoofLinearParameter
  let gateUp: WoofLinearParameter
  let down: WoofLinearParameter

  init(from decoder: any Decoder) throws {
    var fields = try decoder.unkeyedContainer()
    queryKeyValue = try fields.decode(WoofLinearParameter.self)
    attentionOutput = try fields.decode(WoofLinearParameter.self)
    gateUp = try fields.decode(WoofLinearParameter.self)
    down = try fields.decode(WoofLinearParameter.self)
    guard fields.isAtEnd else { throw WoofModelError.invalidConfiguration }
  }
}

struct WoofFlowBlockParameters: Decodable {
  let input: WoofLinearParameter
  let output: WoofLinearParameter

  init(from decoder: any Decoder) throws {
    var fields = try decoder.unkeyedContainer()
    input = try fields.decode(WoofLinearParameter.self)
    output = try fields.decode(WoofLinearParameter.self)
    guard fields.isAtEnd else { throw WoofModelError.invalidConfiguration }
  }
}

struct WoofAffineParameters: Decodable {
  let weight: WoofTensorParameter
  let bias: WoofTensorParameter

  init(from decoder: any Decoder) throws {
    var fields = try decoder.unkeyedContainer()
    weight = try fields.decode(WoofTensorParameter.self)
    bias = try fields.decode(WoofTensorParameter.self)
    guard fields.isAtEnd else { throw WoofModelError.invalidConfiguration }
  }
}
