import AppKit
import QuartzCore
import SilliesCore

@MainActor
final class CompanionView: NSView {
  enum PresentationMode {
    case interactiveCompanion
    case staticPortrait
  }

  let rig: CharacterRig
  let presentationLayer = CALayer()
  var onPickup: (() -> Void)?
  var onDrag: ((CGPoint) -> Void)?
  var onDrop: ((Bool) -> Void)?
  var onContextMenu: (() -> NSMenu)?
  var onStashTargetChanged: ((Bool) -> Void)?
  var onStashDropped: (([String]) -> Void)?
  private var mouseStart = CGPoint.zero
  private var lastDragPoint: CGPoint?
  private var dragged = false
  private var handlingInteraction = false
  private(set) var characterSize: Double
  private let mode: PresentationMode
  private var isPortraitMode: Bool { mode == .staticPortrait }
  private var attachmentPose = AttachmentPose.standing
  private var isAttachedToSurface = true
  private var clippingWindow: CGRect?
  private var clippingDisplay: CGRect?
  private var lastMask: [CGRect] = []
  private let worldMask = CAShapeLayer()
  private let artworkHitTester = ArtworkHitTester()
  private var contactOffset: CGPoint?

  private static let percentScale: Double = 100
  private static let pickupDragThreshold: Double = 3
  private static let maskSubpixelTolerance: CGFloat = 1.5

  static func makePortrait(rig: CharacterRig, size: Double) -> CompanionView {
    CompanionView(rig: rig, size: size, mode: .staticPortrait)
  }

  init(rig: CharacterRig, size: Double, mode: PresentationMode = .interactiveCompanion) {
    self.rig = rig
    self.mode = mode
    characterSize = size
    let baseDimension =
      mode == .staticPortrait
      ? AttachmentPose.designCanvasSize : CompanionWindowLayout.runtimeCanvasDimension
    let dimension = baseDimension * size / Self.percentScale
    super.init(frame: CGRect(x: 0, y: 0, width: dimension, height: dimension))
    wantsLayer = true
    layer?.addSublayer(presentationLayer)
    presentationLayer.addSublayer(rig.root)
    updateRigLayout()
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    if mode == .interactiveCompanion {
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
    if isPortraitMode {
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
      case .standing: (attached && clippingWindow == nil) ? .desktop : .top
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
    guard !isPortraitMode, let panel = window else { return }
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
    guard !isPortraitMode, let panel = window, panel.isVisible, presentationLayer.opacity > 0 else {
      return false
    }
    guard !isProtectedInputPoint(screenPoint) else { return false }
    let local = CGPoint(
      x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    guard bounds.contains(local), let canvas = layer else { return false }
    return artworkHitTester.containsArtwork(in: canvas, at: local)
  }

  func isProtectedInputPoint(_ point: CGPoint) -> Bool {
    guard isAttachedToSurface else { return false }
    if let clippingWindow, clippingWindow.contains(point) {
      return true
    }
    return clippingDisplay.map { !$0.contains(point) } ?? false
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
      isPortraitMode
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
    lastDragPoint = nil
    dragged = false
  }

  override func mouseDragged(with event: NSEvent) {
    continueDrag(at: NSEvent.mouseLocation)
  }

  func continueDrag(at mouse: CGPoint) {
    guard handlingInteraction else { return }
    let delta = CGPoint(x: mouse.x - mouseStart.x, y: mouse.y - mouseStart.y)
    if !dragged && hypot(delta.x, delta.y) > Self.pickupDragThreshold {
      dragged = true
      onPickup?()
    }
    guard dragged, lastDragPoint != mouse else { return }
    lastDragPoint = mouse
    onDrag?(delta)
  }

  override func mouseUp(with event: NSEvent) {
    guard handlingInteraction else { return }
    if dragged { continueDrag(at: NSEvent.mouseLocation) }
    let wasDragged = dragged
    cancelInteraction()
    onDrop?(wasDragged)
  }

  func cancelInteraction() {
    handlingInteraction = false
    dragged = false
    lastDragPoint = nil
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard !isPortraitMode else { return nil }
    return onContextMenu?()
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard !isPortraitMode,
      sender.draggingPasteboard.canReadObject(
        forClasses: [NSURL.self, NSString.self], options: nil)
    else { return [] }
    let point = window?.convertPoint(toScreen: sender.draggingLocation) ?? NSEvent.mouseLocation
    let accepted = containsInteractiveArtwork(at: point)
    onStashTargetChanged?(accepted)
    return accepted ? .copy : []
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) { onStashTargetChanged?(false) }
  override func draggingEnded(_ sender: any NSDraggingInfo) { onStashTargetChanged?(false) }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let point = window?.convertPoint(toScreen: sender.draggingLocation) ?? NSEvent.mouseLocation
    guard containsInteractiveArtwork(at: point) else { return false }
    let items = StashPasteboard.items(from: sender.draggingPasteboard)
    onStashTargetChanged?(false)
    guard !items.isEmpty else { return false }
    onStashDropped?(items)
    return true
  }
}
