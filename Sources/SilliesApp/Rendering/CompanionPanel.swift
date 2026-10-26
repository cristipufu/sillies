import AppKit
import QuartzCore
import SilliesCore

@MainActor
final class CompanionPanel: NSPanel {
  private static let windowLevelOffsetAboveTarget = 1
  private static let hudLevelOffsetAboveCompanion = 1
  static let normalOverlayLevel = NSWindow.Level(
    rawValue: NSWindow.Level.normal.rawValue + windowLevelOffsetAboveTarget)
  static let floatingOverlayLevel = NSWindow.Level(
    rawValue: NSWindow.Level.floating.rawValue + windowLevelOffsetAboveTarget)
  static let overlayLevel = floatingOverlayLevel

  static func overlayLevel(
    forWindowLayer windowLayer: Int,
    isPickedUp: Bool = false
  ) -> NSWindow.Level {
    if isPickedUp || windowLayer >= NSWindow.Level.floating.rawValue {
      return floatingOverlayLevel
    }
    return normalOverlayLevel
  }

  static func hudLevel(forWindowLayer windowLayer: Int) -> NSWindow.Level {
    let companionLevel = overlayLevel(forWindowLayer: windowLayer, isPickedUp: false)
    return NSWindow.Level(rawValue: companionLevel.rawValue + hudLevelOffsetAboveCompanion)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }

  init(view: CompanionView) {
    super.init(
      contentRect: view.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    contentView = view
    view.autoresizingMask = []
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    minSize = .zero
    level = Self.normalOverlayLevel
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    ignoresMouseEvents = true
    acceptsMouseMovedEvents = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    animationBehavior = .none
    let isUnitTest =
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.arguments.contains {
        $0.contains("swift-testing") || $0.hasSuffix(".xctest")
      }
    if isUnitTest { alphaValue = 0 }
  }

  func updateOverlayLevel(forWindowLayer windowLayer: Int, isPickedUp: Bool) {
    let targetLevel = Self.overlayLevel(forWindowLayer: windowLayer, isPickedUp: isPickedUp)
    if level != targetLevel {
      level = targetLevel
    }
  }
}

@MainActor
final class CompanionView: NSView {
  let rig: CharacterRig
  let presentationLayer = CALayer()
  var onPickup: (() -> Void)?
  var onDrag: ((CGPoint) -> Void)?
  var onDrop: ((Bool) -> Void)?
  var onStashDropped: (([String]) -> Void)?
  private var mouseStart = CGPoint.zero
  private var dragged = false
  private var handlingInteraction = false
  private(set) var characterSize: Double
  private let portrait: Bool
  private var attachmentPose = AttachmentPose.standing
  private var isAttachedToSurface = true
  private var clippingWindow: CGRect?
  private var clippingDisplay: CGRect?
  private var lastMask: [CGRect] = []
  private let worldMask = CAShapeLayer()
  private var contactOffset: CGPoint?

  private static let percentScale: Double = 100
  private static let pickupDragThreshold: Double = 3
  private static let minimumVisibleOpacity: Float = 0.1
  private static let minimumStrokeHitWidth: CGFloat = 6
  private static let maskSubpixelTolerance: CGFloat = 1.5

  init(rig: CharacterRig, size: Double, portrait: Bool = false) {
    self.rig = rig
    self.portrait = portrait
    characterSize = size
    let baseDimension =
      portrait ? AttachmentPose.designCanvasSize : CompanionWindowLayout.runtimeCanvasDimension
    let dimension = baseDimension * size / Self.percentScale
    super.init(frame: CGRect(x: 0, y: 0, width: dimension, height: dimension))
    wantsLayer = true
    layer?.addSublayer(presentationLayer)
    presentationLayer.addSublayer(rig.root)
    updateRigLayout()
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    if !portrait {
      registerForDraggedTypes([.string, .URL, .fileURL])
    }
  }

  required init?(coder: NSCoder) { nil }
  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func layout() {
    super.layout()
    updateRigLayout()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateRigLayout()
  }

  func resize(to size: Double) {
    guard characterSize != size else { return }
    characterSize = size
    if portrait {
      let dimension = AttachmentPose.designCanvasSize * size / Self.percentScale
      frame.size = CGSize(width: dimension, height: dimension)
    }
    updateRigLayout()
  }

  func configureSurface(pose: AttachmentPose, window: CGRect?, display: CGRect?) {
    let poseChanged = attachmentPose != pose
    attachmentPose = pose
    rig.setAttachmentPose(pose)
    clippingWindow = window
    clippingDisplay = display
    if poseChanged { updateRigLayout() }
  }

  func panelLayout(at point: CGPoint, attached: Bool) -> CompanionWindowLayout {
    isAttachedToSurface = attached
    let edge: PerchSurface.Edge =
      switch attachmentPose {
      case .standing: clippingWindow == nil ? .desktop : .top
      case .hangingLeft: .left
      case .hangingRight: .right
      }
    return CompanionWindowLayout(
      contact: point, size: characterSize, window: attached ? clippingWindow : nil, edge: edge)
  }

  func applyPanelLayout(_ layout: CompanionWindowLayout) {
    let previous = contactOffset ?? CGPoint(x: bounds.midX, y: bounds.midY)
    let sizeChanged =
      abs(bounds.width - layout.frame.width) > 0.001
      || abs(bounds.height - layout.frame.height) > 0.001
    let changed =
      sizeChanged
      || hypot(previous.x - layout.contactOffset.x, previous.y - layout.contactOffset.y) > 0.001
    contactOffset = layout.contactOffset
    if sizeChanged { setFrameSize(layout.frame.size) }
    if changed { updateRigLayout() }
  }

  func updateWorldMask() {
    guard !portrait, let panel = window else { return }
    let origin = panel.frame.origin
    let visible: CGRect
    if isAttachedToSurface {
      let rawVisible =
        clippingDisplay.map { $0.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds) }
        ?? bounds
      visible =
        abs(rawVisible.minX - bounds.minX) < Self.maskSubpixelTolerance
          && abs(rawVisible.minY - bounds.minY) < Self.maskSubpixelTolerance
          && abs(rawVisible.width - bounds.width) < Self.maskSubpixelTolerance
          && abs(rawVisible.height - bounds.height) < Self.maskSubpixelTolerance
        ? bounds : rawVisible
    } else {
      visible = bounds
    }
    let rawExcluded =
      isAttachedToSurface
      ? (clippingWindow.map { $0.offsetBy(dx: -origin.x, dy: -origin.y).intersection(visible) }
        ?? .null)
      : .null
    let excluded =
      rawExcluded.isNull
        || rawExcluded.width < Self.maskSubpixelTolerance
        || rawExcluded.height < Self.maskSubpixelTolerance
      ? .null : rawExcluded
    let regions = [visible, excluded]
    guard regions != lastMask else { return }
    lastMask = regions
    let path = CGMutablePath()
    if !visible.isNull { path.addRect(visible) }
    if !excluded.isNull { path.addRect(excluded) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    worldMask.frame = bounds
    worldMask.path = path
    worldMask.fillRule = .evenOdd
    if layer?.mask !== worldMask { layer?.mask = worldMask }
    CATransaction.commit()
  }

  func containsInteractiveArtwork(at screenPoint: CGPoint) -> Bool {
    guard !portrait, let panel = window, panel.isVisible, presentationLayer.opacity > 0 else {
      return false
    }
    guard !isProtectedInputPoint(screenPoint) else { return false }
    let local = CGPoint(
      x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    guard bounds.contains(local), let canvas = layer else { return false }
    let presentedCanvas = canvas.presentation() ?? canvas
    for artwork in [rig.stage, rig.hangingArms] {
      let presented = artwork.presentation() ?? artwork
      let point = presented.convert(local, from: presentedCanvas)
      if containsFilledShape(presented, at: point) { return true }
    }
    return false
  }

  func isProtectedInputPoint(_ point: CGPoint) -> Bool {
    guard isAttachedToSurface else { return false }
    if let clippingWindow, clippingWindow.contains(point) {
      return true
    }
    return clippingDisplay.map { !$0.contains(point) } ?? false
  }

  private func containsFilledShape(_ layer: CALayer, at point: CGPoint) -> Bool {
    guard !layer.isHidden, layer.opacity > Self.minimumVisibleOpacity else { return false }
    if let shape = layer as? CAShapeLayer, let path = shape.path {
      if let fill = shape.fillColor, fill.alpha > CGFloat(Self.minimumVisibleOpacity),
        path.contains(point)
      {
        return true
      }
      if let stroke = shape.strokeColor, stroke.alpha > CGFloat(Self.minimumVisibleOpacity),
        shape.lineWidth > 0
      {
        let hitWidth = max(shape.lineWidth, Self.minimumStrokeHitWidth)
        let halfWidth = hitWidth * 0.5
        if path.boundingBoxOfPath.insetBy(dx: -halfWidth, dy: -halfWidth).contains(point),
          path.copy(
            strokingWithWidth: hitWidth,
            lineCap: .round, lineJoin: .round, miterLimit: shape.miterLimit
          ).contains(point)
        {
          return true
        }
      }
    }
    return layer.sublayers?.contains { child in
      containsFilledShape(child, at: child.convert(point, from: layer))
    } ?? false
  }

  private func updateRigLayout() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let contact = contactOffset ?? CGPoint(x: bounds.midX, y: bounds.midY)
    let canvasSize = AttachmentPose.designCanvasSize
    let scale = characterSize / Self.percentScale
    presentationLayer.bounds = bounds
    presentationLayer.anchorPoint = CGPoint(
      x: contact.x / max(bounds.width, 1), y: contact.y / max(bounds.height, 1))
    presentationLayer.position = contact
    rig.root.bounds = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    rig.root.anchorPoint =
      portrait
      ? CGPoint(x: 0.5, y: 0.5)
      : CGPoint(x: attachmentPose.anchor.x / canvasSize, y: attachmentPose.anchor.y / canvasSize)
    rig.root.position = contact
    rig.root.transform = CATransform3DMakeScale(scale, scale, 1)
    rig.updateContentsScale(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    CATransaction.commit()
  }

  override func mouseDown(with event: NSEvent) {
    let point =
      window.map { $0.convertPoint(toScreen: event.locationInWindow) }
      ?? NSEvent.mouseLocation
    handlingInteraction = containsInteractiveArtwork(at: point)
    guard handlingInteraction else { return }
    mouseStart = point
    dragged = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard handlingInteraction else { return }
    let mouse = NSEvent.mouseLocation
    let delta = CGPoint(x: mouse.x - mouseStart.x, y: mouse.y - mouseStart.y)
    if !dragged && hypot(delta.x, delta.y) > Self.pickupDragThreshold {
      dragged = true
      onPickup?()
    }
    if dragged { onDrag?(delta) }
  }

  override func mouseUp(with event: NSEvent) {
    guard handlingInteraction else { return }
    handlingInteraction = false
    onDrop?(dragged)
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard !portrait else { return [] }
    return sender.draggingPasteboard.canReadObject(
      forClasses: [NSURL.self, NSString.self], options: nil) ? .copy : []
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let items = extractDraggedStrings(from: sender.draggingPasteboard)
    guard !items.isEmpty else { return false }
    onStashDropped?(items)
    return true
  }

  private func extractDraggedStrings(from pasteboard: NSPasteboard) -> [String] {
    var collected: [String] = []
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
      for url in urls {
        collected.append(url.isFileURL ? url.path : url.absoluteString)
      }
    }
    if let text = pasteboard.string(forType: .string)?.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !text.isEmpty,
      !collected.contains(text)
    {
      collected.append(text)
    }
    return collected
  }
}
