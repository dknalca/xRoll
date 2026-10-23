import SpriteKit

/// Tokens y geometría compartidos por la presentación del gameplay.
/// No contienen estado musical ni toman decisiones de puntuación.
enum GameplayVisualTheme {
    static let background = SKColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1)
    static let backdropWall = SKColor(red: 0.035, green: 0.055, blue: 0.088, alpha: 1)
    static let backdropCyan = SKColor(red: 0.16, green: 0.78, blue: 0.94, alpha: 1)
    static let backdropMagenta = SKColor(red: 0.80, green: 0.39, blue: 0.88, alpha: 1)
    static let highway = SKColor(red: 0.055, green: 0.071, blue: 0.090, alpha: 1)
    static let deck = SKColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1)
    static let surface = SKColor(red: 0.075, green: 0.094, blue: 0.118, alpha: 1)
    static let padBody = SKColor(red: 0.050, green: 0.075, blue: 0.112, alpha: 1)
    static let padFace = SKColor(red: 0.098, green: 0.131, blue: 0.174, alpha: 1)
    static let text = SKColor(red: 0.945, green: 0.953, blue: 0.961, alpha: 1)
    static let textSecondary = SKColor(red: 0.639, green: 0.671, blue: 0.710, alpha: 1)
    static let perfect = SKColor(red: 0.388, green: 0.902, blue: 0.745, alpha: 1)
    static let good = SKColor(red: 0.455, green: 0.753, blue: 0.988, alpha: 1)
    static let regular = SKColor(red: 1, green: 0.831, blue: 0.231, alpha: 1)
    static let miss = SKColor(red: 1, green: 0.420, blue: 0.420, alpha: 1)
    static let labelFont = "Avenir Next Demi Bold"

    static func soundAccent(_ sound: String) -> SKColor {
        switch sound {
        case "kick": return SKColor(red: 0.15, green: 0.72, blue: 1.0, alpha: 1)
        case "rim": return SKColor(red: 0.78, green: 0.59, blue: 0.25, alpha: 1)
        case "snare": return SKColor(red: 1.0, green: 0.37, blue: 0.48, alpha: 1)
        case "clap": return SKColor(red: 0.72, green: 0.48, blue: 1.0, alpha: 1)
        case "hihat_closed": return SKColor(red: 0.35, green: 0.86, blue: 0.62, alpha: 1)
        case "hihat_open": return SKColor(red: 0.27, green: 0.78, blue: 0.82, alpha: 1)
        case "tom_low": return SKColor(red: 0.18, green: 0.64, blue: 0.76, alpha: 1)
        case "tom_high": return SKColor(red: 0.24, green: 0.78, blue: 0.84, alpha: 1)
        case "crash": return SKColor(red: 1.0, green: 0.76, blue: 0.24, alpha: 1)
        case "ride": return SKColor(red: 0.92, green: 0.58, blue: 0.22, alpha: 1)
        default: return SKColor(red: 0.39, green: 0.82, blue: 0.92, alpha: 1)
        }
    }

    static func padSymbolPath(for sound: String) -> CGPath {
        let path = CGMutablePath()
        switch sound {
        case "kick", "tom_low", "tom_high":
            path.addEllipse(in: CGRect(x: -5.5, y: -5.5, width: 11, height: 11))
            path.move(to: CGPoint(x: -2, y: 0))
            path.addLine(to: CGPoint(x: 2, y: 0))
        case "hihat_closed", "hihat_open", "ride", "crash":
            path.move(to: CGPoint(x: -8, y: -1))
            path.addLine(to: CGPoint(x: 8, y: -1))
            path.move(to: CGPoint(x: -5, y: 3))
            path.addLine(to: CGPoint(x: 5, y: 3))
            if sound == "hihat_open" || sound == "crash" {
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 0, y: 9))
            }
        default:
            path.move(to: CGPoint(x: -7, y: -4))
            path.addLine(to: CGPoint(x: -2, y: 5))
            path.addLine(to: CGPoint(x: 2, y: -3))
            path.addLine(to: CGPoint(x: 7, y: 4))
        }
        return path
    }
}

/// Proyección 2.5D de carriles por sonido. La coordenada temporal sigue siendo lineal;
/// solo se estrecha la pista hacia el horizonte para dar profundidad.
struct GameplayProjection {
    let size: CGSize
    let hitLineY: CGFloat
    let laneCount: Int
    var topInset: CGFloat = 16
    var topWidthRatio: CGFloat = 0.74

    var horizonY: CGFloat { max(hitLineY + 1, size.height - topInset) }

    /// Las ventanas grandes añaden márgenes, no carriles desproporcionados.
    /// En pantallas estrechas el espacio disponible sigue siendo el límite.
    private var preferredTrackWidth: CGFloat {
        switch laneCount {
        case ...1: return 320
        case 2: return 400
        case 3: return 600
        case 4: return 720
        default: return min(1_000, 720 + CGFloat(laneCount - 4) * 80)
        }
    }

    /// Prolonga los límites de un carril por debajo de la línea de golpe para
    /// que el receptor conserve la misma fuga y la misma pendiente lateral.
    func padGeometry(slot: Int, height: CGFloat) -> ProjectedPadGeometry {
        let boundedSlot = max(0, min(laneCount - 1, slot))
        let padHeight = max(1, height)
        let backTrackWidth = trackWidth(at: 0)
        let projectionHeight = max(1, horizonY - hitLineY)
        let widthGrowth = backTrackWidth * (1 - topWidthRatio) * padHeight / projectionHeight
        let frontTrackWidth = backTrackWidth + widthGrowth
        let slotCenterFraction = (CGFloat(boundedSlot) + 0.5) / CGFloat(laneCount) - 0.5
        let backCenterX = size.width / 2 + slotCenterFraction * backTrackWidth
        let frontCenterX = size.width / 2 + slotCenterFraction * frontTrackWidth

        return ProjectedPadGeometry(
            center: CGPoint(x: (backCenterX + frontCenterX) / 2, y: hitLineY - padHeight / 2),
            backCenterX: backCenterX,
            frontCenterX: frontCenterX,
            backWidth: backTrackWidth / CGFloat(laneCount),
            frontWidth: frontTrackWidth / CGFloat(laneCount),
            height: padHeight
        )
    }

    func depth(for millisecondsRemaining: Double, displayLeadMilliseconds: Double) -> CGFloat {
        let lead = max(1, displayLeadMilliseconds)
        return CGFloat(max(0, min(1, millisecondsRemaining / lead)))
    }

    func y(at depth: CGFloat) -> CGFloat {
        hitLineY + (horizonY - hitLineY) * clamp(depth)
    }

    func trackWidth(at depth: CGFloat) -> CGFloat {
        let bottomWidth = max(1, min(size.width * 0.92, preferredTrackWidth))
        let ratio = 1 - (1 - topWidthRatio) * clamp(depth)
        return bottomWidth * ratio
    }

    func x(atSlotBoundary boundary: Int, depth: CGFloat) -> CGFloat {
        let slotFraction = CGFloat(max(0, min(laneCount, boundary))) / CGFloat(laneCount)
        return size.width / 2 + (slotFraction - 0.5) * trackWidth(at: depth)
    }

    func point(slot: Int, depth: CGFloat) -> CGPoint {
        let boundedSlot = max(0, min(laneCount - 1, slot))
        return CGPoint(
            x: x(atSlotBoundary: boundedSlot, depth: depth) + trackWidth(at: depth) / CGFloat(laneCount * 2),
            y: y(at: depth)
        )
    }

    /// Silueta local de una nota: sus dos bordes son paralelos a los bordes
    /// proyectados de SU carril. Se construye al activar el nodo, no por frame.
    func notePath(slot: Int) -> CGPath {
        let laneWidth = trackWidth(at: 0) / CGFloat(laneCount)
        // Un tamaño acotado mantiene la nota reconocible al cambiar de frase;
        // solo se reduce cuando el propio carril no permite conservarlo.
        let width = min(44, max(8, laneWidth - 6))
        let height: CGFloat = 34
        let heightRange = max(1, horizonY - hitLineY)
        let centerSlope = (point(slot: slot, depth: 1).x - point(slot: slot, depth: 0).x) / heightRange
        let widthSlope = (trackWidth(at: 1) - trackWidth(at: 0)) / (CGFloat(laneCount) * heightRange) * (width / laneWidth)
        let halfHeight = height / 2
        let topWidth = width + widthSlope * halfHeight
        let bottomWidth = width - widthSlope * halfHeight
        let topCenter = centerSlope * halfHeight
        let bottomCenter = -topCenter

        let path = CGMutablePath()
        path.move(to: CGPoint(x: topCenter - topWidth / 2, y: halfHeight))
        path.addLine(to: CGPoint(x: topCenter + topWidth / 2, y: halfHeight))
        path.addLine(to: CGPoint(x: bottomCenter + bottomWidth / 2, y: -halfHeight))
        path.addLine(to: CGPoint(x: bottomCenter - bottomWidth / 2, y: -halfHeight))
        path.closeSubpath()
        return path
    }

    func lanePath(slot: Int) -> CGPath {
        let lane = max(0, min(laneCount - 1, slot))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x(atSlotBoundary: lane, depth: 0), y: hitLineY))
        path.addLine(to: CGPoint(x: x(atSlotBoundary: lane + 1, depth: 0), y: hitLineY))
        path.addLine(to: CGPoint(x: x(atSlotBoundary: lane + 1, depth: 1), y: horizonY))
        path.addLine(to: CGPoint(x: x(atSlotBoundary: lane, depth: 1), y: horizonY))
        path.closeSubpath()
        return path
    }

    /// Onda lateral normalizada, anclada a ambos extremos del separador.
    /// Las fases se precalculan al crear el escenario y se reutilizan en cada frame.
    static func separatorWavePath(phase: Int, phaseCount: Int = 12, cycles: Double = 2.4) -> CGPath {
        let path = CGMutablePath()
        let phaseOffset = Double(phase) / Double(max(1, phaseCount))
        let samples = 48
        for sample in 0...samples {
            let progress = Double(sample) / Double(samples)
            let envelope = sin(Double.pi * progress)
            let displacement = sin(2 * Double.pi * (cycles * progress - phaseOffset)) * envelope
            let point = CGPoint(x: displacement, y: progress)
            if sample == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        return path
    }

    func boundaryPath(_ boundary: Int) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x(atSlotBoundary: boundary, depth: 0), y: hitLineY))
        path.addLine(to: CGPoint(x: x(atSlotBoundary: boundary, depth: 1), y: horizonY))
        return path
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }
}

/// Geometría local de un receptor proyectado, derivada de los bordes del carril.
struct ProjectedPadGeometry {
    let center: CGPoint
    let backCenterX: CGFloat
    let frontCenterX: CGFloat
    let backWidth: CGFloat
    let frontWidth: CGFloat
    let height: CGFloat

    var centerShift: CGFloat { frontCenterX - backCenterX }

    func path(sideInset: CGFloat = 0, verticalInset: CGFloat = 0) -> CGPath {
        let safeVerticalInset = min(max(0, verticalInset), height / 2)
        let upperProgress = safeVerticalInset / height
        let lowerProgress = 1 - upperProgress
        let upperCenter = backCenterX + centerShift * upperProgress
        let lowerCenter = backCenterX + centerShift * lowerProgress
        let upperWidth = backWidth + (frontWidth - backWidth) * upperProgress
        let lowerWidth = backWidth + (frontWidth - backWidth) * lowerProgress
        let upperHalfWidth = max(1, upperWidth / 2 - sideInset)
        let lowerHalfWidth = max(1, lowerWidth / 2 - sideInset)
        let upperY = height / 2 - safeVerticalInset
        let lowerY = -height / 2 + safeVerticalInset
        let path = CGMutablePath()

        path.move(to: CGPoint(x: upperCenter - center.x - upperHalfWidth, y: upperY))
        path.addLine(to: CGPoint(x: upperCenter - center.x + upperHalfWidth, y: upperY))
        path.addLine(to: CGPoint(x: lowerCenter - center.x + lowerHalfWidth, y: lowerY))
        path.addLine(to: CGPoint(x: lowerCenter - center.x - lowerHalfWidth, y: lowerY))
        path.closeSubpath()
        return path
    }

    func centerOffset(atY y: CGFloat) -> CGFloat {
        -centerShift * max(-0.5, min(0.5, y / height))
    }
}

/// Efectos transitorios de SpriteKit, separados del reloj y del scoring.
final class GameplayEffectsRenderer {
    let node = SKNode()
    private var particles = [SKShapeNode]()
    private let judgementLabel = SKLabelNode()
    private var impactRings = [SKShapeNode]()
    private var extraWaves = [SKShapeNode]()
    private var streakFlash: SKSpriteNode?

    init() {
        node.zPosition = 18
    }

    func showJudgement(_ text: String, at point: CGPoint, maximumWidth: CGFloat, color: SKColor, reducesMotion: Bool) {
        let label = judgementLabel
        label.removeAction(forKey: "judgement")
        label.text = text
        label.fontName = GameplayVisualTheme.labelFont
        label.fontSize = 13
        label.fontColor = color
        label.position = point
        label.alpha = 1
        label.setScale(1)
        let naturalWidth = max(1, label.frame.width)
        label.xScale = min(1, maximumWidth / naturalWidth)
        label.zPosition = 2
        if label.parent == nil { node.addChild(label) }
        if reducesMotion {
            label.run(.sequence([.fadeOut(withDuration: 0.26), .removeFromParent()]), withKey: "judgement")
        } else {
            label.yScale = 0.92
            label.run(.sequence([
                .group([.scaleY(to: 1, duration: 0.09), .fadeAlpha(to: 1, duration: 0.09)]),
                .group([.moveBy(x: 0, y: -3, duration: 0.26), .fadeOut(withDuration: 0.26)]),
                .removeFromParent()
            ]), withKey: "judgement")
        }
    }

    func showImpact(at point: CGPoint, color: SKColor, particleCount: Int, reducesMotion: Bool) {
        guard !reducesMotion else { return }
        if let ring = reusableRing() {
            ring.removeAllActions()
            ring.path = CGPath(ellipseIn: CGRect(x: -17, y: -8, width: 34, height: 16), transform: nil)
            ring.fillColor = .clear
            ring.strokeColor = color.withAlphaComponent(0.9)
            ring.lineWidth = 2
            ring.position = CGPoint(x: point.x, y: point.y - 8)
            ring.alpha = 0.9
            ring.xScale = 0.72
            ring.yScale = 0.82
            ring.zPosition = 1
            node.addChild(ring)
            ring.run(.sequence([
                .group([.scaleX(to: 1.42, duration: 0.16), .scaleY(to: 1.08, duration: 0.16), .fadeOut(withDuration: 0.16)]),
                .removeFromParent()
            ]))
        }
        emitParticles(from: CGPoint(x: point.x, y: point.y - 9), color: color, count: particleCount)
    }

    func showExtra(at point: CGPoint, laneWidth: CGFloat, color: SKColor, reducesMotion: Bool) {
        guard !reducesMotion, let wave = reusableWave() else { return }
        wave.removeAllActions()
        let halfWidth = max(8, laneWidth * 0.32)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: point.x - halfWidth, y: point.y - 8))
        path.addQuadCurve(to: CGPoint(x: point.x + halfWidth, y: point.y - 8), control: CGPoint(x: point.x, y: point.y - 22))
        wave.path = path
        wave.strokeColor = color
        wave.lineWidth = 2
        wave.glowWidth = 0
        wave.zPosition = 1
        wave.alpha = 1
        wave.xScale = 1
        node.addChild(wave)
        wave.run(.sequence([
            .group([.scaleX(to: 1.35, duration: 0.20), .fadeOut(withDuration: 0.20)]),
            .removeFromParent()
        ]))
    }

    func showStreak(at point: CGPoint, color: SKColor, reducesMotion: Bool) {
        guard !reducesMotion else { return }
        let flash: SKSpriteNode
        if let streakFlash, streakFlash.parent == nil {
            flash = streakFlash
        } else if streakFlash != nil {
            return
        } else {
            let created = SKSpriteNode(color: color, size: .zero)
            streakFlash = created
            flash = created
        }
        flash.removeAllActions()
        flash.color = color
        flash.colorBlendFactor = 1
        flash.size = CGSize(width: 52, height: 2)
        flash.position = CGPoint(x: point.x, y: point.y - 7)
        flash.alpha = 0.76
        flash.xScale = 0.65
        flash.zPosition = 1
        node.addChild(flash)
        flash.run(.sequence([
            .group([.scaleX(to: 1.25, duration: 0.10), .fadeAlpha(to: 0.48, duration: 0.10)]),
            .fadeOut(withDuration: 0.16),
            .removeFromParent()
        ]))
    }

    private func emitParticles(from origin: CGPoint, color: SKColor, count: Int) {
        guard count > 0 else { return }
        for index in 0..<count {
            guard let particle = reusableParticle() else { return }
            particle.removeAllActions()
            particle.fillColor = color.withAlphaComponent(0.86)
            particle.strokeColor = .clear
            particle.position = origin
            particle.alpha = 1
            particle.setScale(index.isMultiple(of: 2) ? 0.72 : 0.52)
            particle.zPosition = 1
            node.addChild(particle)
            let lateral = CGFloat(index - count / 2) * 5
            let downward = CGFloat(7 + (index % 3) * 4)
            particle.run(.sequence([
                .group([.moveBy(x: lateral, y: -downward, duration: 0.20), .fadeOut(withDuration: 0.20), .scale(to: 0.18, duration: 0.20)]),
                .removeFromParent()
            ]))
        }
    }

    private func reusableParticle() -> SKShapeNode? {
        if let particle = particles.first(where: { $0.parent == nil }) { return particle }
        guard particles.count < 24 else { return nil }
        let particle = SKShapeNode(circleOfRadius: 3.5)
        particles.append(particle)
        return particle
    }

    private func reusableRing() -> SKShapeNode? {
        if let ring = impactRings.first(where: { $0.parent == nil }) { return ring }
        guard impactRings.count < 16 else { return nil }
        let ring = SKShapeNode()
        impactRings.append(ring)
        return ring
    }

    private func reusableWave() -> SKShapeNode? {
        if let wave = extraWaves.first(where: { $0.parent == nil }) { return wave }
        guard extraWaves.count < 4 else { return nil }
        let wave = SKShapeNode()
        extraWaves.append(wave)
        return wave
    }
}
