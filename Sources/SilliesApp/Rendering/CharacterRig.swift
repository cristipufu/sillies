import AppKit
import QuartzCore
import SilliesCore

extension NSColor {
  convenience init(hex: String, alpha: CGFloat = 1) {
    let value = UInt32(hex, radix: 16) ?? 0
    self.init(
      srgbRed: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: alpha)
  }
}

/// A 128-point vector rig. Artwork and animation are independent of behavior selection.
@MainActor
class CharacterRig {
  private static let floorShadowOpacity: Float = 0.12
  private static let feedbackChangeEpsilon: Double = 0.015
  private static let feedbackAnimationInterval: Double = 1.0 / 30.0
  private static let feedbackTimingFunction = CAMediaTimingFunction(name: .linear)
  private static let feedbackVerticalStretchRatio: Double = 0.6
  private static let uprightTransformTolerance: CGFloat = 0.0001

  let root = CALayer()
  let facing = CALayer()
  let workspaceMotion = CALayer()
  let stage = CALayer()
  let torso = CALayer()
  let head = CALayer()
  let leftArm = CALayer()
  let rightArm = CALayer()
  let leftFoot = CALayer()
  let rightFoot = CALayer()
  let accessory = CALayer()
  let eyes = CALayer()
  let closedEyes = CALayer()
  let delight = CALayer()
  let sleepMark = CATextLayer()
  let dust = CALayer()
  let hangingArms = CALayer()
  let secondaryGrip = CALayer()
  private(set) var attachmentPose = AttachmentPose.standing
  var isHanging: Bool { attachmentPose.isHanging }
  var isUpright: Bool {
    abs(root.transform.m12) < Self.uprightTransformTolerance
      && abs(root.transform.m21) < Self.uprightTransformTolerance
  }
  let gripFill: String
  let sleeveFill: String
  let gripOutline: String
  private var standingFacingRight = true
  private var floorShadow: CAShapeLayer?
  private(set) var facingRight = true
  private(set) var feedbackAnimationCount = 0
  private(set) var behaviorResetGeneration = 0
  private var lastLean: Double = 0
  private var lastStretch: Double = 0
  private var feedbackAnimation: WindowFeedbackAnimation?
  private var lastFeedbackAnimationTime: Double = -.infinity
  private struct DetailPose {
    let layer: CALayer
    let opacity: Float
  }
  private var details: [DetailPose] = []
  private var playfulProps: PlayfulRigProps?
  private var playfulArticulation: PlayfulArticulation?

  func preparePlayfulProps() -> PlayfulRigProps {
    if let playfulProps { return playfulProps }
    let props = PlayfulRigProps(rig: self)
    playfulProps = props
    playfulArticulation = PlayfulArticulation(rig: self)
    return props
  }

  func articulatePlayfulPose() { playfulArticulation?.activate() }

  func holdPlayfulProp(
    at point: CGPoint, hand: PlayfulArticulation.Hand = .right, angle: CGFloat = 0.9
  ) {
    _ = preparePlayfulProps()
    playfulArticulation?.holdProp(at: point, hand: hand, angle: angle)
  }

  /// Artwork registers local moving details once; interruption and Reduce Motion reset them.
  func addDetail(
    _ layer: CALayer, to parent: CALayer, frame: CGRect, restingOpacity: Float = 1
  ) {
    layer.frame = frame
    layer.opacity = restingOpacity
    parent.addSublayer(layer)
    details.append(DetailPose(layer: layer, opacity: restingOpacity))
  }

  private var animatableLayers: [CALayer] {
    [
      root, stage, torso, head, leftArm, rightArm, leftFoot, rightFoot,
      accessory, eyes, closedEyes, delight, sleepMark, dust, hangingArms, secondaryGrip,
    ]
  }

  init(
    gripFill: String = "F3C38F", sleeveFill: String = "F3C38F", gripOutline: String = "B77D55"
  ) {
    self.gripFill = gripFill
    self.sleeveFill = sleeveFill
    self.gripOutline = gripOutline
    stage.name = ArtworkHitTester.interactiveRootName
    hangingArms.name = ArtworkHitTester.interactiveRootName
    delight.name = ArtworkHitTester.decorationName
    let canvasSize = AttachmentPose.designCanvasSize
    root.frame = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    facing.frame = root.bounds
    workspaceMotion.frame = root.bounds
    stage.frame = root.bounds
    torso.frame = root.bounds
    let standingAnchor = AttachmentPose.standing.anchor
    for layer in [workspaceMotion, stage] {
      layer.anchorPoint = CGPoint(
        x: standingAnchor.x / canvasSize, y: standingAnchor.y / canvasSize)
      layer.position = standingAnchor
    }
    root.addSublayer(facing)
    facing.addSublayer(workspaceMotion)
    workspaceMotion.addSublayer(stage)
    floorShadow = shape(
      on: root, path: CGPath(ellipseIn: CGRect(x: 39, y: 16, width: 50, height: 5), transform: nil),
      fill: "352B3D", opacity: Self.floorShadowOpacity)
    root.insertSublayer(facing, at: 1)
    for layer in [accessory, torso, leftFoot, rightFoot, leftArm, rightArm, head, delight] {
      stage.addSublayer(layer)
    }
    configureSleepMark()
    configureDelightMarks()
    configureDust()
    configureHangingArms()
  }

  private func configureSleepMark() {
    sleepMark.string = "z"
    sleepMark.font = NSFont.roundedFont(ofSize: 19, weight: .bold)
    sleepMark.fontSize = 19
    sleepMark.foregroundColor = NSColor(hex: "8E859F").cgColor
    sleepMark.frame = CGRect(x: 92, y: 94, width: 20, height: 27)
    sleepMark.contentsScale = 2
    sleepMark.opacity = 0
    root.addSublayer(sleepMark)
  }

  private func configureDelightMarks() {
    delight.frame = root.bounds
    for rect in [
      CGRect(x: 15, y: 83, width: 9, height: 9), CGRect(x: 108, y: 70, width: 7, height: 7),
    ] {
      let path = CGMutablePath()
      path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.midX + 1.4, y: rect.midY + 1.4))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.midX + 1.4, y: rect.midY - 1.4))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.midX - 1.4, y: rect.midY - 1.4))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.midX - 1.4, y: rect.midY + 1.4))
      path.closeSubpath()
      shape(on: delight, path: path, fill: "E5AA60")
    }
    delight.opacity = 0
  }

  private func configureDust() {
    dust.frame = root.bounds
    for (x, y, radius) in [(37.0, 24.0, 10.0), (50, 23, 14), (70, 24, 12), (86, 23, 9)] {
      oval(
        on: dust, CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2),
        "E4DDEC")
    }
    dust.opacity = 0
    root.insertSublayer(dust, below: facing)
  }

  private func configureHangingArms() {
    hangingArms.frame = root.bounds
    secondaryGrip.frame = root.bounds
    facing.addSublayer(hangingArms)
    let upper = CGMutablePath()
    upper.move(to: CGPoint(x: 85, y: 59))
    upper.addQuadCurve(to: CGPoint(x: 110, y: 101), control: CGPoint(x: 101, y: 68))
    shape(on: hangingArms, path: upper, fill: nil, stroke: gripOutline, lineWidth: 12)
    shape(on: hangingArms, path: upper, fill: nil, stroke: sleeveFill, lineWidth: 9)
    let lower = CGMutablePath()
    lower.move(to: CGPoint(x: 42, y: 53))
    lower.addCurve(
      to: CGPoint(x: 110, y: 77), control1: CGPoint(x: 61, y: 35), control2: CGPoint(x: 91, y: 58))
    shape(on: secondaryGrip, path: lower, fill: nil, stroke: gripOutline, lineWidth: 12)
    shape(on: secondaryGrip, path: lower, fill: nil, stroke: sleeveFill, lineWidth: 9)
    hangingArms.addSublayer(secondaryGrip)
    for (parent, y) in [(hangingArms, 96.0), (secondaryGrip, 72.0)] {
      CharacterHandArtwork.draw(on: parent, at: CGPoint(x: 105, y: y), rig: self)
    }
    hangingArms.opacity = 0
  }

  func updateContentsScale(_ scale: CGFloat) {
    guard root.contentsScale != scale else { return }
    root.contentsScale = scale
    sleepMark.contentsScale = scale
  }

  func setFacing(right: Bool) {
    let changed = standingFacingRight != right || facingRight != right
    standingFacingRight = right
    guard !isHanging, changed else { return }
    facingRight = right
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    facing.transform = CATransform3DMakeScale(right ? 1 : -1, 1, 1)
    CATransaction.commit()
  }

  func setAttachmentPose(_ pose: AttachmentPose) {
    guard attachmentPose != pose else { return }
    attachmentPose = pose
    resetWorkspaceFeedback()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    facingRight = pose.isHanging ? pose == .hangingLeft : standingFacingRight
    facing.transform = CATransform3DMakeScale(facingRight ? 1 : -1, 1, 1)
    let pivot = pose.isHanging ? AttachmentPose.hangingLeft.anchor : AttachmentPose.standing.anchor
    let canvasSize = AttachmentPose.designCanvasSize
    workspaceMotion.anchorPoint = CGPoint(x: pivot.x / canvasSize, y: pivot.y / canvasSize)
    workspaceMotion.position = pivot
    leftArm.opacity = pose.isHanging ? 0 : 1
    rightArm.opacity = pose.isHanging ? 0 : 1
    hangingArms.opacity = pose.isHanging ? 1 : 0
    floorShadow?.opacity = pose.isHanging ? 0 : Self.floorShadowOpacity
    CATransaction.commit()
  }

  func resetPose() {
    resetBehaviorPose()
    resetWorkspaceFeedback()
  }

  private func resetWorkspaceFeedback() {
    lastLean = 0
    lastStretch = 0
    feedbackAnimation = nil
    lastFeedbackAnimationTime = -.infinity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    workspaceMotion.removeAllAnimations()
    workspaceMotion.transform = CATransform3DIdentity
    CATransaction.commit()
  }

  func resetBehaviorPose() {
    behaviorResetGeneration += 1
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playfulProps?.reset()
    playfulArticulation?.restore()
    for layer in animatableLayers { layer.removeAllAnimations() }
    for detail in details {
      detail.layer.removeAllAnimations()
      detail.layer.transform = CATransform3DIdentity
      detail.layer.opacity = detail.opacity
    }
    for layer in [stage, torso, head, leftArm, rightArm, leftFoot, rightFoot, accessory] {
      layer.transform = CATransform3DIdentity
    }
    eyes.opacity = 1
    closedEyes.opacity = 0
    delight.opacity = 0
    sleepMark.opacity = 0
    dust.opacity = 0
    leftArm.opacity = isHanging ? 0 : 1
    rightArm.opacity = isHanging ? 0 : 1
    hangingArms.opacity = isHanging ? 1 : 0
    floorShadow?.opacity = isHanging ? 0 : Self.floorShadowOpacity
    CATransaction.commit()
  }

  func workspaceFeedback(lean: Double, stretch: Double, settling: Bool = false) {
    if !settling,
      abs(lean - lastLean) < Self.feedbackChangeEpsilon,
      abs(stretch - lastStretch) < Self.feedbackChangeEpsilon
    {
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    if !settling, now - lastFeedbackAnimationTime < Self.feedbackAnimationInterval {
      return
    }
    lastLean = lean
    lastStretch = stretch
    lastFeedbackAnimationTime = settling ? -.infinity : now
    let old = feedbackAnimation?.value(at: now) ?? WindowMotionFeedback(lean: 0, stretch: 0)
    let next = WindowMotionFeedback(lean: lean, stretch: stretch)
    let motion = WindowFeedbackAnimation(
      from: old, to: next, at: now, style: settling ? .settling : .following)
    feedbackAnimation = motion
    let transform = feedbackTransform(next)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    workspaceMotion.transform = transform
    CATransaction.commit()
    let animation: CABasicAnimation
    if settling {
      let spring = CASpringAnimation(keyPath: "transform")
      spring.mass = WindowFeedbackAnimation.springMass
      spring.stiffness = WindowFeedbackAnimation.springStiffness
      spring.damping = WindowFeedbackAnimation.springDamping
      animation = spring
    } else {
      animation = CABasicAnimation(keyPath: "transform")
      animation.timingFunction = Self.feedbackTimingFunction
    }
    animation.duration = motion.duration
    animation.beginTime = workspaceMotion.convertTime(CACurrentMediaTime(), from: nil)
    animation.fromValue = NSValue(caTransform3D: feedbackTransform(old))
    animation.toValue = NSValue(caTransform3D: transform)
    feedbackAnimationCount += 1
    workspaceMotion.add(animation, forKey: "workspaceFeedback")
  }

  private func feedbackTransform(_ feedback: WindowMotionFeedback) -> CATransform3D {
    CATransform3DScale(
      CATransform3DMakeRotation(facingRight ? feedback.lean : -feedback.lean, 0, 0, 1),
      1 + feedback.stretch, 1 - feedback.stretch * Self.feedbackVerticalStretchRatio, 1)
  }

  @discardableResult
  func shape(
    on parent: CALayer, path: CGPath, fill: String?, stroke: String? = nil,
    lineWidth: CGFloat = 2, opacity: Float = 1
  ) -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.path = path
    layer.fillColor = fill.map { NSColor(hex: $0).cgColor }
    layer.strokeColor = stroke.map { NSColor(hex: $0).cgColor }
    layer.lineWidth = lineWidth
    layer.lineCap = .round
    layer.lineJoin = .round
    layer.opacity = opacity
    parent.addSublayer(layer)
    return layer
  }

  func oval(on parent: CALayer, _ rect: CGRect, _ fill: String, stroke: String? = nil) {
    shape(on: parent, path: CGPath(ellipseIn: rect, transform: nil), fill: fill, stroke: stroke)
  }

  func pill(
    on parent: CALayer, _ rect: CGRect, _ fill: String, radius: CGFloat? = nil,
    stroke: String? = nil
  ) {
    shape(
      on: parent,
      path: CGPath(
        roundedRect: rect, cornerWidth: radius ?? rect.height / 2,
        cornerHeight: radius ?? rect.height / 2, transform: nil), fill: fill, stroke: stroke)
  }

  func line(on parent: CALayer, points: [CGPoint], color: String, width: CGFloat = 2) {
    guard let first = points.first else { return }
    let path = CGMutablePath()
    path.move(to: first)
    for point in points.dropFirst() { path.addLine(to: point) }
    shape(on: parent, path: path, fill: nil, stroke: color, lineWidth: width)
  }

  func makeEyes(
    in face: CALayer, left: CGFloat, right: CGFloat, y: CGFloat, color: String = "433136"
  ) {
    eyes.frame = face.bounds
    closedEyes.frame = face.bounds
    face.addSublayer(eyes)
    face.addSublayer(closedEyes)
    for x in [left, right] {
      pill(on: eyes, CGRect(x: x - 3.3, y: y - 4.5, width: 6.6, height: 10), color)
      oval(on: eyes, CGRect(x: x - 1.7, y: y + 1.8, width: 2, height: 2.5), "FFFFFF")
      let path = CGMutablePath()
      path.move(to: CGPoint(x: x - 4.5, y: y))
      path.addQuadCurve(to: CGPoint(x: x + 4.5, y: y), control: CGPoint(x: x, y: y + 4))
      shape(on: closedEyes, path: path, fill: nil, stroke: color, lineWidth: 2.3)
    }
    closedEyes.opacity = 0
  }
}

extension NSFont {
  static func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
      ?? font
  }
}
