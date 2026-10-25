import AppKit

func color(_ hex: UInt32) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func fill(_ rect: NSRect, _ hex: UInt32, radius: CGFloat) {
  color(hex).setFill()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("Sillies.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  let background = NSBezierPath(
    roundedRect: NSRect(x: 25, y: 25, width: 974, height: 974), xRadius: 216, yRadius: 216)
  NSGradient(starting: color(0xF1E9FC), ending: color(0xD5CDF1))!.draw(in: background, angle: -65)
  fill(NSRect(x: 135, y: 184, width: 758, height: 30), 0xB6AACF, radius: 15)
  fill(NSRect(x: 132, y: 213, width: 755, height: 33), 0xFFF9EE, radius: 16)
  let ears = NSBezierPath()
  ears.move(to: NSPoint(x: 206, y: 512))
  ears.line(to: NSPoint(x: 193, y: 764))
  ears.line(to: NSPoint(x: 381, y: 672))
  ears.close()
  ears.move(to: NSPoint(x: 474, y: 655))
  ears.line(to: NSPoint(x: 641, y: 763))
  ears.line(to: NSPoint(x: 658, y: 490))
  ears.close()
  color(0xE8AC72).setFill()
  ears.fill()
  fill(NSRect(x: 228, y: 244, width: 394, height: 364), 0xE9AD74, radius: 140)
  fill(NSRect(x: 171, y: 389, width: 503, height: 306), 0xF5C792, radius: 146)
  fill(NSRect(x: 283, y: 400, width: 280, height: 145), 0xFFE5BF, radius: 70)
  for x in [328.0, 509.0] {
    fill(NSRect(x: x, y: 512, width: 28, height: 51), 0x543D3B, radius: 14)
    fill(NSRect(x: x + 7, y: 544, width: 8, height: 12), 0xFFFFFF, radius: 4)
  }
  fill(NSRect(x: 404, y: 472, width: 36, height: 23), 0xBB8072, radius: 11)
  fill(NSRect(x: 306, y: 244, width: 80, height: 67), 0xF9D4A6, radius: 25)
  fill(NSRect(x: 468, y: 244, width: 80, height: 67), 0xF9D4A6, radius: 25)
  fill(NSRect(x: 290, y: 365, width: 270, height: 40), 0xD27E79, radius: 15)
  fill(NSRect(x: 637, y: 244, width: 169, height: 222), 0x3E3A57, radius: 63)
  fill(NSRect(x: 577, y: 413, width: 288, height: 240), 0x3E3A57, radius: 107)
  fill(NSRect(x: 601, y: 460, width: 239, height: 96), 0xF5E0C5, radius: 42)
  fill(NSRect(x: 586, y: 564, width: 268, height: 44), 0xA69DDF, radius: 17)
  for x in [659.0, 759.0] { fill(NSRect(x: x, y: 490, width: 18, height: 32), 0x393345, radius: 9) }
  fill(NSRect(x: 639, y: 324, width: 167, height: 28), 0xA69DDF, radius: 8)
  fill(NSRect(x: 623, y: 244, width: 64, height: 36), 0x353146, radius: 17)
  fill(NSRect(x: 751, y: 244, width: 64, height: 36), 0x353146, radius: 17)
  let star = NSBezierPath()
  star.move(to: NSPoint(x: 780, y: 821))
  star.line(to: NSPoint(x: 795, y: 778))
  star.line(to: NSPoint(x: 838, y: 763))
  star.line(to: NSPoint(x: 795, y: 748))
  star.line(to: NSPoint(x: 780, y: 705))
  star.line(to: NSPoint(x: 765, y: 748))
  star.line(to: NSPoint(x: 722, y: 763))
  star.line(to: NSPoint(x: 765, y: 778))
  star.close()
  color(0xFFFFFF).setFill()
  star.fill()
  NSGraphicsContext.restoreGraphicsState()
  let png = bitmap.representation(using: .png, properties: [:])!
  if [16, 32, 128, 256, 512].contains(size) {
    try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
  }
  if [32, 64, 256, 512, 1024].contains(size) {
    try png.write(to: iconset.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))
  }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = [
  "-c", "icns", iconset.path, "-o", output.appendingPathComponent("Sillies.icns").path,
]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
