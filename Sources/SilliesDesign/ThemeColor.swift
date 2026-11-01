import Foundation

/// Validated sRGB values. Platform adapters choose how to draw them.
package struct ThemeColor: Codable, Equatable, Sendable {
  package let red: Double
  package let green: Double
  package let blue: Double

  package init(hex: String) throws {
    guard hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
      let value = UInt32(hex.dropFirst(), radix: 16)
    else {
      throw ThemeCatalogFailure.invalid(String(localized: "Colors must use #RRGGBB."))
    }
    red = Double((value >> 16) & 255) / 255
    green = Double((value >> 8) & 255) / 255
    blue = Double(value & 255) / 255
  }
  package init(from decoder: any Decoder) throws {
    try self.init(hex: decoder.singleValueContainer().decode(String.self))
  }
  package func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(
      String(
        format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()),
        Int((blue * 255).rounded())))
  }
  package func contrast(with other: ThemeColor) -> Double {
    let first = luminance
    let second = other.luminance
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
  }
  private var luminance: Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
}
