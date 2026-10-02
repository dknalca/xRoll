import AudioToolbox
import SpriteKit
import XRollCore

enum GridGuideSubdivision: Int, CaseIterable, Identifiable {
    case quarter = 1
    case eighth = 2
    case sixteenth = 4
    case thirtySecond = 8

    var id: Int { rawValue }
    var label: String { "1/\(rawValue * 4)" }
}

enum PracticeViewZoom: String, CaseIterable, Identifiable {
    case close
    case standard
    case wide
    case overview

    var id: String { rawValue }
    var bars: Double {
        switch self {
        case .close: return 0.5
        case .standard: return 1
        case .wide: return 1.5
        case .overview: return 2
        }
    }
    var label: String {
        switch self {
        case .close: return "½"
        case .standard: return "1"
        case .wide: return "1½"
        case .overview: return "2"
        }
    }
}

struct SceneVisualClockSnapshot {
    let renderHostTime: UInt64
    let estimatedPresentationHostTime: UInt64
    let frameIntervalMilliseconds: Double
    let predictedLeadMilliseconds: Double
}

private struct PracticeSceneFeedbackEvent {
    let feedbackID: String
    let sound: String
    let judgement: RhythmJudgement?
    let noteIndex: Int?
    let offsetMilliseconds: Double?
    let occurredAtHostTime: UInt64?
}

private struct GameplaySeparatorVisual {
    let node: SKShapeNode
    let baseWidth: CGFloat
    let isActive: Bool
    let boundary: Int
    let basePath: CGPath
    let waveOrigin: CGPoint
    let waveRotation: CGFloat
    let length: CGFloat
}

final class PracticeScene: SKScene {
    var onFeedbackConsumed: ((String, UInt64) -> Void)?
    private let timeline: ExerciseTimeline
    private let startHostTime: UInt64
    private let anticipationMilliseconds: Double
    private let noteByIndex: [Int: ScheduledExerciseNote]
    private let slotBySound: [String: Int]
    private let slotByNoteIndex: [Int: Int]
    private let targetSlotsBySound: [String: [Int]]
    private let soundLabels: [String: String]
    private let showsSoundLabels: Bool
    private let showsNotes: Bool
    /// Notas que la ayuda reducida oculta sin retirarlas de la sesión puntuable.
    private let hiddenGuideNoteIndices: Set<Int>
    private let emphasizesPlayerNotes: Bool
    private var gridGuide: GridGuideSubdivision
    private var viewZoom: PracticeViewZoom
    private var reducesMotion: Bool
    private var usesLowPowerVisuals: Bool
    private var predictsPresentationFrame: Bool
    private var previousUpdateTime: TimeInterval?
    private var smoothedFrameMilliseconds: Double = 0
    private let visualClockLock = NSLock()
    private var latestVisualClockSnapshot: SceneVisualClockSnapshot?
    private let feedbackQueueLock = NSLock()
    private var feedbackQueue = [PracticeSceneFeedbackEvent?](repeating: nil, count: 128)
    private var feedbackQueueReadIndex = 0
    private var feedbackQueueWriteIndex = 0
    private var feedbackQueueCount = 0
    private var droppedFeedbackCount: UInt64 = 0
    var droppedVisualFeedbackEvents: UInt64 {
        feedbackQueueLock.lock()
        defer { feedbackQueueLock.unlock() }
        return droppedFeedbackCount
    }
    /// Nil = todas las voces son del jugador. Un conjunto permite atenuar en
    /// pantalla las voces que xRoll toca como acompañamiento.
    private let playerSounds: Set<String>?
    private let staticLayer = SKNode()
    private let effectsRenderer = GameplayEffectsRenderer()
    private var activeNoteNodes: [Int: SKShapeNode] = [:]
    private var noteNodePool = [SKShapeNode]()
    private var activePulseLines: [Int: SKSpriteNode] = [:]
    private var pulseLinePool = [SKSpriteNode]()
    private var activeChannelGlows = [Int: SKShapeNode]()
    private var separatorVisuals = [Int: GameplaySeparatorVisual]()
    private var separatorWavePaths = [CGPath]()
    private let hitY: CGFloat = 82
    private let barLabel = SKLabelNode()
    private let beatLabel = SKLabelNode()
    private let streakLabel = SKLabelNode()
    private var streakPanel: SKShapeNode?
    private let progressFill = SKSpriteNode(color: GameplayVisualTheme.perfect, size: .zero)
    private var hitGlow: SKSpriteNode?
    private var hitLine: SKSpriteNode?
    private var targetBySound: [String: [SKShapeNode]] = [:]
    private var targetBaseFills: [String: [SKColor]] = [:]
    private var consumedNoteIndices = Set<Int>()
    private var feedbackNoteIndices = Set<Int>()
    private var lastPulseBeat = -1
    private var lastBarText = ""
    private var lastBeatText = ""
    private var successfulStreak = 0

    private var projection: GameplayProjection {
        GameplayProjection(size: size, hitLineY: hitY)
    }

    init(timeline: ExerciseTimeline, startHostTime: UInt64, anticipationMilliseconds: Double, slotBySound: [String: Int], slotByNoteIndex: [Int: Int] = [:], targetSlotsBySound: [String: [Int]] = [:], soundLabels: [String: String], showsSoundLabels: Bool = true, showsNotes: Bool = true, hiddenGuideNoteIndices: Set<Int> = [], emphasizesPlayerNotes: Bool = false, playerSounds: Set<String>? = nil, gridGuide: GridGuideSubdivision = .eighth, viewZoom: PracticeViewZoom = .standard, reducesMotion: Bool = false, usesLowPowerVisuals: Bool = false, predictsPresentationFrame: Bool = false) {
        self.timeline = timeline
        self.startHostTime = startHostTime
        self.anticipationMilliseconds = anticipationMilliseconds
        self.noteByIndex = Dictionary(uniqueKeysWithValues: timeline.notes.map { ($0.index, $0) })
        self.slotBySound = slotBySound
        self.slotByNoteIndex = slotByNoteIndex
        self.targetSlotsBySound = targetSlotsBySound.isEmpty ? slotBySound.mapValues { [$0] } : targetSlotsBySound
        self.soundLabels = soundLabels
        self.showsSoundLabels = showsSoundLabels
        self.showsNotes = showsNotes
        self.hiddenGuideNoteIndices = hiddenGuideNoteIndices
        self.emphasizesPlayerNotes = emphasizesPlayerNotes
        self.playerSounds = playerSounds
        self.gridGuide = gridGuide
        self.viewZoom = viewZoom
        self.reducesMotion = reducesMotion
        self.usesLowPowerVisuals = usesLowPowerVisuals
        self.predictsPresentationFrame = predictsPresentationFrame
        super.init(size: CGSize(width: 960, height: 520))
        scaleMode = .resizeFill
        backgroundColor = GameplayVisualTheme.background
    }

    required init?(coder: NSCoder) { nil }

    var visualClockSnapshot: SceneVisualClockSnapshot? {
        visualClockLock.lock()
        defer { visualClockLock.unlock() }
        return latestVisualClockSnapshot
    }

    func setPredictsPresentationFrame(_ enabled: Bool) {
        visualClockLock.lock()
        guard predictsPresentationFrame != enabled else {
            visualClockLock.unlock()
            return
        }
        predictsPresentationFrame = enabled
        previousUpdateTime = nil
        smoothedFrameMilliseconds = 0
        latestVisualClockSnapshot = nil
        visualClockLock.unlock()
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        view.shouldCullNonVisibleNodes = true
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        if staticLayer.parent == nil { addChild(staticLayer) }
        if effectsRenderer.node.parent == nil { addChild(effectsRenderer.node) }
        rebuildStaticLayer()
        rebuildPulseLines()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard view != nil else { return }
        rebuildStaticLayer()
        let projection = self.projection
        for (index, node) in activeNoteNodes {
            guard let note = noteByIndex[index],
                  let slot = slotByNoteIndex[index] ?? slotBySound[note.sound] else { continue }
            node.path = projection.notePath(slot: slot)
        }
        for line in activePulseLines.values { line.size.width = size.width }
    }

    private func rebuildStaticLayer() {
        staticLayer.removeAllChildren()
        targetBySound.removeAll()
        targetBaseFills.removeAll()
        activeChannelGlows.removeAll()
        separatorVisuals.removeAll()
        let soundsInTimeline = Set(timeline.notes.map(\.sound))
        let activeSounds = Set(soundsInTimeline.filter { playerSounds?.contains($0) ?? true })
        let activeSlots = Set(activeSounds.flatMap { sound in
            targetSlotsBySound[sound] ?? slotBySound[sound].map { [$0] } ?? []
        })
        let projection = self.projection
        separatorWavePaths = (0..<12).map { GameplayProjection.separatorWavePath(phase: $0) }
        let background = SKSpriteNode(color: GameplayVisualTheme.background, size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.zPosition = -20
        staticLayer.addChild(background)

        // Una carretera trapezoidal aporta profundidad sin comprimir el eje de
        // tiempo: los slots conservan su orden y la línea de golpe permanece fija.
        let roadPath = CGMutablePath()
        roadPath.move(to: CGPoint(x: projection.x(atSlotBoundary: 0, depth: 0), y: hitY))
        roadPath.addLine(to: CGPoint(x: projection.x(atSlotBoundary: 16, depth: 0), y: hitY))
        roadPath.addLine(to: CGPoint(x: projection.x(atSlotBoundary: 16, depth: 1), y: projection.horizonY))
        roadPath.addLine(to: CGPoint(x: projection.x(atSlotBoundary: 0, depth: 1), y: projection.horizonY))
        roadPath.closeSubpath()
        let road = SKShapeNode(path: roadPath)
        road.fillColor = GameplayVisualTheme.highway
        road.strokeColor = SKColor.white.withAlphaComponent(0.16)
        road.lineWidth = 1
        road.zPosition = -8
        staticLayer.addChild(road)

        for index in 0..<16 {
            let isActive = activeSlots.contains(index)
            let lane = SKShapeNode(path: projection.lanePath(slot: index))
            lane.fillColor = isActive
                ? color(forSlot: index).withAlphaComponent(0.045)
                : SKColor.white.withAlphaComponent(0.012)
            lane.strokeColor = .clear
            lane.lineWidth = 0
            lane.zPosition = -7
            staticLayer.addChild(lane)
            if isActive {
                let channelGlow = SKShapeNode(path: projection.lanePath(slot: index))
                channelGlow.fillColor = color(forSlot: index).withAlphaComponent(0.22)
                channelGlow.strokeColor = .clear
                channelGlow.alpha = 0.07
                channelGlow.zPosition = -6
                staticLayer.addChild(channelGlow)
                activeChannelGlows[index] = channelGlow
            }
        }

        for boundary in 0...16 {
            let divider = SKShapeNode(path: projection.boundaryPath(boundary))
            let isActiveEdge = activeSlots.contains(boundary) || activeSlots.contains(boundary - 1)
            let activeSlot: Int?
            if boundary < 16 && activeSlots.contains(boundary) { activeSlot = boundary }
            else if boundary > 0 && activeSlots.contains(boundary - 1) { activeSlot = boundary - 1 }
            else { activeSlot = nil }
            divider.strokeColor = (activeSlot.map(color(forSlot:)) ?? SKColor.white)
                .withAlphaComponent(isActiveEdge ? 0.16 : 0.045)
            divider.lineWidth = boundary.isMultiple(of: 4) ? 1.1 : 0.65
            divider.zPosition = -5
            staticLayer.addChild(divider)
            let bottom = CGPoint(x: projection.x(atSlotBoundary: boundary, depth: 0), y: hitY)
            let top = CGPoint(x: projection.x(atSlotBoundary: boundary, depth: 1), y: projection.horizonY)
            let deltaX = top.x - bottom.x
            let deltaY = top.y - bottom.y
            separatorVisuals[boundary] = GameplaySeparatorVisual(
                node: divider,
                baseWidth: divider.lineWidth,
                isActive: isActiveEdge,
                boundary: boundary,
                basePath: projection.boundaryPath(boundary),
                waveOrigin: bottom,
                waveRotation: -atan2(Double(deltaX), Double(deltaY)),
                length: hypot(deltaX, deltaY)
            )
        }

        // Marcas laterales de sección y horizonte: dan escala y velocidad, pero
        // dejan el centro de lectura despejado.
        for beat in 1...8 {
            let depth = CGFloat(beat) / 9
            let width = projection.trackWidth(at: depth)
            let marker = SKSpriteNode(
                color: SKColor.white.withAlphaComponent(beat.isMultiple(of: 2) ? 0.055 : 0.025),
                size: CGSize(width: width, height: beat.isMultiple(of: 2) ? 1 : 0.6)
            )
            marker.position = CGPoint(x: size.width / 2, y: projection.y(at: depth))
            marker.zPosition = -4
            staticLayer.addChild(marker)
        }
        let horizon = SKSpriteNode(color: GameplayVisualTheme.perfect.withAlphaComponent(0.42), size: CGSize(width: projection.trackWidth(at: 1), height: 1.5))
        horizon.position = CGPoint(x: size.width / 2, y: projection.horizonY)
        horizon.zPosition = -3
        staticLayer.addChild(horizon)

        let deck = SKSpriteNode(color: GameplayVisualTheme.deck, size: CGSize(width: projection.trackWidth(at: 0), height: hitY))
        deck.position = CGPoint(x: size.width / 2, y: hitY / 2)
        deck.zPosition = 1
        staticLayer.addChild(deck)
        addCyberpunkSidePanels(using: projection)

        let judgementPlateWidth = max(1, min(280, size.width - 24))
        let judgementPlate = SKShapeNode(rectOf: CGSize(width: judgementPlateWidth, height: 24), cornerRadius: 8)
        judgementPlate.fillColor = GameplayVisualTheme.surface.withAlphaComponent(0.98)
        judgementPlate.strokeColor = GameplayVisualTheme.perfect.withAlphaComponent(0.28)
        judgementPlate.lineWidth = 1
        judgementPlate.position = CGPoint(x: size.width / 2, y: 14)
        judgementPlate.zPosition = 12
        staticLayer.addChild(judgementPlate)

        let hitGlow = SKSpriteNode(color: GameplayVisualTheme.perfect.withAlphaComponent(0.16), size: CGSize(width: projection.trackWidth(at: 0), height: 9))
        hitGlow.position = CGPoint(x: size.width / 2, y: hitY)
        hitGlow.zPosition = 6
        staticLayer.addChild(hitGlow)
        self.hitGlow = hitGlow
        let hitLine = SKSpriteNode(color: GameplayVisualTheme.text, size: CGSize(width: projection.trackWidth(at: 0), height: 2))
        hitLine.position = CGPoint(x: size.width / 2, y: hitY)
        hitLine.zPosition = 11
        staticLayer.addChild(hitLine)
        self.hitLine = hitLine

        // El HUD flota sobre el escenario, separado visualmente de las notas.
        let hud = SKShapeNode(rectOf: CGSize(width: 180, height: 48), cornerRadius: 14)
        hud.fillColor = GameplayVisualTheme.deck.withAlphaComponent(0.94)
        hud.strokeColor = SKColor.white.withAlphaComponent(0.12)
        hud.lineWidth = 1
        hud.position = CGPoint(x: size.width - 108, y: size.height - 34)
        hud.zPosition = 30
        staticLayer.addChild(hud)
        barLabel.fontName = GameplayVisualTheme.labelFont
        barLabel.fontSize = 13
        barLabel.fontColor = GameplayVisualTheme.text
        barLabel.horizontalAlignmentMode = .left
        barLabel.position = CGPoint(x: size.width - 190, y: size.height - 30)
        barLabel.zPosition = 31
        staticLayer.addChild(barLabel)
        beatLabel.fontName = "Avenir Next Regular"
        beatLabel.fontSize = 11
        beatLabel.fontColor = GameplayVisualTheme.textSecondary
        beatLabel.horizontalAlignmentMode = .left
        beatLabel.position = CGPoint(x: size.width - 190, y: size.height - 46)
        beatLabel.zPosition = 31
        staticLayer.addChild(beatLabel)
        let progressTrack = SKSpriteNode(color: SKColor.white.withAlphaComponent(0.16), size: CGSize(width: 72, height: 4))
        progressTrack.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.position = CGPoint(x: size.width - 94, y: size.height - 39)
        progressTrack.zPosition = 31
        staticLayer.addChild(progressTrack)
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressFill.position = progressTrack.position
        progressFill.zPosition = 32
        staticLayer.addChild(progressFill)
        let streakWidth = min(146, max(84, size.width * 0.27))
        let streakPanel = SKShapeNode(rectOf: CGSize(width: streakWidth, height: 44), cornerRadius: 11)
        streakPanel.position = CGPoint(x: 12 + streakWidth / 2, y: size.height - 34)
        streakPanel.fillColor = GameplayVisualTheme.deck.withAlphaComponent(0.94)
        streakPanel.strokeColor = GameplayVisualTheme.perfect.withAlphaComponent(0.58)
        streakPanel.lineWidth = 1
        streakPanel.zPosition = 30
        staticLayer.addChild(streakPanel)
        self.streakPanel = streakPanel
        streakLabel.fontName = GameplayVisualTheme.labelFont
        streakLabel.fontSize = size.width < 400 ? 12 : 16
        streakLabel.fontColor = GameplayVisualTheme.perfect
        streakLabel.verticalAlignmentMode = .center
        streakLabel.horizontalAlignmentMode = .center
        streakLabel.zPosition = 1
        streakPanel.addChild(streakLabel)
        refreshStreakHUD(animated: false)
        for (sound, slots) in targetSlotsBySound {
            let isPlayerSound = activeSounds.contains(sound)
            for slot in slots {
                let x = projection.point(slot: slot, depth: 0).x
                let isRecommended = slotBySound[sound] == slot
                let accent = color(forSlot: slot)
                let padWidth = max(14, projection.trackWidth(at: 0) / 16 - 7)
                let target = SKShapeNode(path: GameplayProjection.padPath(width: padWidth, height: 48))
                target.fillColor = GameplayVisualTheme.padBody.withAlphaComponent(isPlayerSound ? 1 : 0.72)
                target.strokeColor = accent.withAlphaComponent(isPlayerSound ? (isRecommended ? 0.90 : 0.42) : 0.22)
                target.lineWidth = isRecommended ? 1.5 : 1
                target.position = CGPoint(x: x, y: hitY - 24)
                target.zPosition = 8
                staticLayer.addChild(target)
                targetBySound[sound, default: []].append(target)
                targetBaseFills[sound, default: []].append(target.fillColor)

                let face = SKShapeNode(path: GameplayProjection.padPath(width: max(8, padWidth - 6), height: 40))
                face.name = "padFace"
                face.fillColor = GameplayVisualTheme.padFace.withAlphaComponent(isPlayerSound ? 1 : 0.75)
                face.strokeColor = SKColor.white.withAlphaComponent(isPlayerSound ? 0.12 : 0.05)
                face.lineWidth = 0.8
                face.position = CGPoint(x: 0, y: 1)
                face.zPosition = 1
                target.addChild(face)

                let lightBar = SKSpriteNode(color: accent.withAlphaComponent(isPlayerSound ? 0.88 : 0.25), size: CGSize(width: max(6, padWidth - 14), height: 2.5))
                lightBar.position = CGPoint(x: 0, y: 17)
                lightBar.zPosition = 2
                target.addChild(lightBar)

                let symbol = SKShapeNode(path: GameplayVisualTheme.padSymbolPath(for: sound))
                symbol.strokeColor = accent.withAlphaComponent(isPlayerSound ? 0.92 : 0.32)
                symbol.fillColor = .clear
                symbol.lineWidth = 1.6
                symbol.lineCap = .round
                symbol.position = CGPoint(x: 0, y: 5)
                symbol.yScale = 0.72
                symbol.zPosition = 2
                target.addChild(symbol)

                if showsSoundLabels {
                    let label = SKLabelNode(text: compactSoundLabel(for: sound))
                    label.fontName = GameplayVisualTheme.labelFont
                    label.fontSize = 9
                    label.fontColor = GameplayVisualTheme.text.withAlphaComponent(isPlayerSound ? (isRecommended ? 1 : 0.72) : 0.40)
                    label.verticalAlignmentMode = .center
                    label.horizontalAlignmentMode = .center
                    label.position = CGPoint(x: 0, y: -11)
                    label.zPosition = 3
                    label.xScale = min(1, max(1, padWidth - 10) / max(1, label.frame.width))
                    target.addChild(label)
                }
            }
        }
    }

    private func addCyberpunkSidePanels(using projection: GameplayProjection) {
        // PCB único por lado: pistas paralelas con ramas escalonadas y vías.
        // Todos los puntos usan la misma proyección que la carretera; sin edificios
        // superpuestos ni elementos en el plano de las notas.
        for isLeft in [true, false] {
            let accent = isLeft ? GameplayVisualTheme.backdropCyan : GameplayVisualTheme.backdropMagenta
            let wall = SKShapeNode(path: backdropPolygon([
                sidePoint(fraction: 0, depth: 0, isLeft: isLeft, projection: projection),
                sidePoint(fraction: 1, depth: 0, isLeft: isLeft, projection: projection),
                sidePoint(fraction: 1, depth: 1, isLeft: isLeft, projection: projection),
                sidePoint(fraction: 0, depth: 1, isLeft: isLeft, projection: projection)
            ]))
            wall.fillColor = GameplayVisualTheme.backdropWall
            wall.strokeColor = .clear
            wall.zPosition = -19
            staticLayer.addChild(wall)
            for track in 0..<3 {
                let fraction = CGFloat(track + 1) * 0.23
                let path = CGMutablePath()
                path.move(to: sidePoint(fraction: fraction, depth: 0.06, isLeft: isLeft, projection: projection))
                path.addLine(to: sidePoint(fraction: fraction, depth: 0.94, isLeft: isLeft, projection: projection))
                for step in 0..<3 {
                    let depth = CGFloat(step) * 0.25 + 0.17 + CGFloat(track) * 0.065
                    path.move(to: sidePoint(fraction: fraction, depth: depth, isLeft: isLeft, projection: projection))
                    path.addLine(to: sidePoint(fraction: fraction + 0.115, depth: depth + 0.035, isLeft: isLeft, projection: projection))
                    path.addLine(to: sidePoint(fraction: fraction + 0.115, depth: depth + 0.09, isLeft: isLeft, projection: projection))
                    let via = SKShapeNode(circleOfRadius: track == 1 ? 2.8 : 2.2)
                    via.position = sidePoint(fraction: fraction + 0.115, depth: depth + 0.09, isLeft: isLeft, projection: projection)
                    via.fillColor = GameplayVisualTheme.backdropWall
                    via.strokeColor = accent.withAlphaComponent(0.78)
                    via.lineWidth = 1
                    via.zPosition = -10
                    staticLayer.addChild(via)
                }
                let conductor = SKShapeNode(path: path)
                conductor.strokeColor = accent.withAlphaComponent(track == 1 ? 0.64 : 0.36)
                conductor.lineWidth = track == 1 ? 1.8 : 1.2
                conductor.fillColor = .clear
                conductor.zPosition = -11
                staticLayer.addChild(conductor)
            }
        }
    }

    private func sidePoint(fraction: CGFloat, depth: CGFloat, isLeft: Bool, projection: GameplayProjection) -> CGPoint {
        let edge = projection.x(atSlotBoundary: isLeft ? 0 : 16, depth: depth)
        let margin = isLeft ? edge : size.width - edge
        let direction: CGFloat = isLeft ? -1 : 1
        return CGPoint(x: edge + direction * margin * fraction, y: projection.y(at: depth))
    }

    private func backdropPolygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func compactSoundLabel(for sound: String) -> String {
        switch sound {
        case "hihat_closed": return "HH Clo"
        case "hihat_open": return "HH Opn"
        case "clap": return "Clap"
        case "tom_low": return "Tom G."
        case "tom_high": return "Tom A."
        default: return soundLabels[sound] ?? sound
        }
    }

    func setGridGuide(_ guide: GridGuideSubdivision) {
        guard gridGuide != guide else { return }
        gridGuide = guide
        if view != nil { rebuildPulseLines() }
    }

    func setViewZoom(_ zoom: PracticeViewZoom) {
        guard viewZoom != zoom else { return }
        viewZoom = zoom
    }

    func setReducesMotion(_ enabled: Bool) {
        reducesMotion = enabled
    }

    private var usesMinimalFeedback: Bool { reducesMotion || usesLowPowerVisuals }

    private func rebuildPulseLines() {
        for line in activePulseLines.values {
            line.removeFromParent()
            pulseLinePool.append(line)
        }
        activePulseLines.removeAll(keepingCapacity: true)
    }

    override func update(_ currentTime: TimeInterval) {
        let presentationLead = estimatedPresentationLeadMilliseconds(at: currentTime)
        let renderHostTime = AudioClock.currentHostTime()
        let presentationHostTime = AudioClock.hostTime(afterMilliseconds: presentationLead, from: renderHostTime)
        visualClockLock.lock()
        latestVisualClockSnapshot = SceneVisualClockSnapshot(
            renderHostTime: renderHostTime,
            estimatedPresentationHostTime: presentationHostTime,
            frameIntervalMilliseconds: smoothedFrameMilliseconds,
            predictedLeadMilliseconds: presentationLead
        )
        visualClockLock.unlock()
        drainFeedbackEvents(consumedAtHostTime: renderHostTime)
        let now = AudioClock.milliseconds(from: startHostTime, to: presentationHostTime)
        let displayLeadMilliseconds = min(anticipationMilliseconds, timeline.barDurationMilliseconds * viewZoom.bars)
        let projection = self.projection
        let elapsed = max(0, now)
        let patternPosition = elapsed.truncatingRemainder(dividingBy: timeline.patternDurationMilliseconds)
        let barPosition = patternPosition.truncatingRemainder(dividingBy: timeline.barDurationMilliseconds)
        let beatDuration = timeline.barDurationMilliseconds / 4
        updateStreakVisuals(elapsedMilliseconds: elapsed)
        let absoluteBeat = Int(max(0, now) / beatDuration)
        if absoluteBeat != lastPulseBeat {
            lastPulseBeat = absoluteBeat
            pulseHitLine(isBar: absoluteBeat.isMultiple(of: 4))
        }
        let currentBar = min(timeline.bars, Int(patternPosition / timeline.barDurationMilliseconds) + 1)
        let barText = "VUELTA \(Int(elapsed / timeline.patternDurationMilliseconds) + 1) · C \(currentBar)/\(timeline.bars)"
        if barText != lastBarText {
            lastBarText = barText
            barLabel.text = barText
        }
        let beatText = "Pulso \(min(4, Int(barPosition / beatDuration) + 1)) de 4"
        if beatText != lastBeatText {
            lastBeatText = beatText
            beatLabel.text = beatText
        }
        progressFill.size = CGSize(width: 72 * CGFloat(barPosition / timeline.barDurationMilliseconds), height: 4)
        updatePulseLines(now: now, displayLeadMilliseconds: displayLeadMilliseconds, projection: projection)
        prepareVisibleNotes(from: now - 120, through: now + displayLeadMilliseconds)
        var notesToRecycle = [Int]()
        for (index, node) in activeNoteNodes {
            guard let note = noteByIndex[index] else {
                notesToRecycle.append(index)
                continue
            }
            // La animación de impacto reutiliza el nodo de la nota, incluso en
            // transferencia donde las notas normales permanecen ocultas.
            if feedbackNoteIndices.contains(note.index) { continue }
            guard showsNotes, !hiddenGuideNoteIndices.contains(note.index) else { node.isHidden = true; continue }
            let remaining = note.timeMilliseconds - now
            guard let slot = slotByNoteIndex[note.index] ?? slotBySound[note.sound] else {
                node.isHidden = true
                if remaining < -120 { notesToRecycle.append(index) }
                continue
            }
            guard !consumedNoteIndices.contains(note.index) else {
                node.isHidden = true
                continue
            }
            let isHidden = remaining > displayLeadMilliseconds || remaining < -120
            if node.isHidden != isHidden { node.isHidden = isHidden }
            if remaining < -120 {
                notesToRecycle.append(index)
                continue
            }
            guard !isHidden else { continue }
            let depth = projection.depth(for: remaining, displayLeadMilliseconds: displayLeadMilliseconds)
            node.position = projection.point(slot: slot, depth: depth)
            let proximity = CGFloat(max(0, min(1, 1 - remaining / min(beatDuration, max(1, displayLeadMilliseconds)))))
            // La nota gana presencia al acercarse: no es un marcador estático,
            // sino el objeto que el músico debe "recibir" en el punto de golpe.
            node.alpha = 0.58 + 0.42 * proximity
            let scale = (0.70 + 0.30 * (1 - depth)) * (0.88 + 0.16 * proximity)
            // La misma escala en ambos ejes conserva la pendiente de los lados
            // del trapecio; la nota se reduce con la anchura del carril al fondo.
            node.setScale(scale * projection.trackWidth(at: depth) / projection.trackWidth(at: 0))
        }
        for index in notesToRecycle { recycleNoteNode(at: index) }
    }

    /// SpriteKit prepara el siguiente frame antes de que el panel lo muestre.
    /// En iOS avanzamos solo la imagen por el intervalo de frame observado; el
    /// score y los eventos MIDI/táctiles conservan su hostTime original.
    private func estimatedPresentationLeadMilliseconds(at currentTime: TimeInterval) -> Double {
        visualClockLock.lock()
        defer { visualClockLock.unlock() }
        guard predictsPresentationFrame else { return 0 }
        defer { previousUpdateTime = currentTime }
        guard let previousUpdateTime else { return smoothedFrameMilliseconds }
        let interval = (currentTime - previousUpdateTime) * 1_000
        guard (4...50).contains(interval) else { return smoothedFrameMilliseconds }
        smoothedFrameMilliseconds = smoothedFrameMilliseconds == 0
            ? interval
            : smoothedFrameMilliseconds * 0.8 + interval * 0.2
        return smoothedFrameMilliseconds
    }

    private func prepareVisibleNotes(from startTime: Double, through finalTime: Double) {
        guard showsNotes else { return }
        let visibleRange = timeline.noteRange(from: startTime, through: finalTime)
        let obsoleteIndices = activeNoteNodes.keys.filter { index in
            guard !feedbackNoteIndices.contains(index), let note = noteByIndex[index] else { return false }
            return note.timeMilliseconds < startTime || note.timeMilliseconds > finalTime
        }
        for index in obsoleteIndices { recycleNoteNode(at: index) }
        for position in visibleRange {
            let note = timeline.notes[position]
            guard !consumedNoteIndices.contains(note.index), !hiddenGuideNoteIndices.contains(note.index) else { continue }
            _ = activateNoteNode(for: note)
        }
    }

    private func activateNoteNode(for note: ScheduledExerciseNote) -> SKShapeNode {
        if let node = activeNoteNodes[note.index] { return node }
        let node = noteNodePool.popLast() ?? makeNoteNode()
        let isPlayerSound = playerSounds?.contains(note.sound) ?? true
        let color = color(forSound: note.sound)
        node.removeAllActions()
        if let slot = slotByNoteIndex[note.index] ?? slotBySound[note.sound] {
            node.path = projection.notePath(slot: slot)
        }
        node.fillColor = color.withAlphaComponent(isPlayerSound ? 1 : 0.38)
        node.strokeColor = color.withAlphaComponent(isPlayerSound ? 1 : 0.32)
        node.lineWidth = emphasizesPlayerNotes && isPlayerSound ? 2.4 : 1.8
        node.zPosition = 10
        node.alpha = 1
        node.setScale(1)
        node.isHidden = true
        addChild(node)
        activeNoteNodes[note.index] = node
        return node
    }

    private func makeNoteNode() -> SKShapeNode {
        let node = SKShapeNode()
        node.lineWidth = 1.8
        node.zPosition = 10
        return node
    }

    private func recycleNoteNode(at index: Int) {
        guard let node = activeNoteNodes.removeValue(forKey: index) else { return }
        node.removeAllActions()
        node.removeFromParent()
        node.isHidden = true
        feedbackNoteIndices.remove(index)
        noteNodePool.append(node)
    }

    private func updatePulseLines(now: Double, displayLeadMilliseconds: Double, projection: GameplayProjection) {
        let guidesPerBeat = gridGuide.rawValue
        let guideDuration = timeline.barDurationMilliseconds / 4 / Double(guidesPerBeat)
        let firstPulseTime = -anticipationMilliseconds
        let finalNoteTime = timeline.notes.last?.timeMilliseconds ?? 0
        let maximumIndex = max(0, Int(floor((finalNoteTime + anticipationMilliseconds - firstPulseTime) / guideDuration)))
        let firstVisible = max(0, Int(ceil((now - 120 - firstPulseTime) / guideDuration)))
        let lastVisible = min(maximumIndex, Int(floor((now + displayLeadMilliseconds - firstPulseTime) / guideDuration)))
        let visibleRange = firstVisible...max(firstVisible, lastVisible)

        let obsoleteLines = activePulseLines.keys.filter { !visibleRange.contains($0) }
        for index in obsoleteLines {
            guard let line = activePulseLines.removeValue(forKey: index) else { continue }
            line.removeFromParent()
            pulseLinePool.append(line)
        }
        guard firstVisible <= lastVisible else { return }
        for index in visibleRange {
            let line = activePulseLines[index] ?? activatePulseLine(at: index, guidesPerBeat: guidesPerBeat)
            let time = firstPulseTime + Double(index) * guideDuration
            let depth = projection.depth(for: time - now, displayLeadMilliseconds: displayLeadMilliseconds)
            line.position = CGPoint(x: size.width / 2, y: projection.y(at: depth))
            line.size.width = projection.trackWidth(at: depth)
        }
    }

    private func activatePulseLine(at index: Int, guidesPerBeat: Int) -> SKSpriteNode {
        let isBar = index.isMultiple(of: guidesPerBeat * 4)
        let isBeat = index.isMultiple(of: guidesPerBeat)
        let opacity: CGFloat
        if isBar { opacity = 0.55 }
        else if isBeat { opacity = 0.20 }
        else if guidesPerBeat == 2 || (guidesPerBeat >= 4 && index.isMultiple(of: guidesPerBeat / 2)) { opacity = 0.14 }
        else if guidesPerBeat == 8 && index.isMultiple(of: 2) { opacity = 0.10 }
        else { opacity = 0.07 }
        let line = pulseLinePool.popLast() ?? SKSpriteNode(color: .clear, size: .zero)
        line.color = isBar ? GameplayVisualTheme.perfect : GameplayVisualTheme.text
        line.alpha = opacity
        line.size = CGSize(width: projection.trackWidth(at: 1), height: isBar ? 2 : 1)
        line.zPosition = 2
        addChild(line)
        activePulseLines[index] = line
        return line
    }

    /// La racha solo modula presentación: no participa en score ni en timing.
    private func updateStreakVisuals(elapsedMilliseconds: Double) {
        let boundedStreak = min(successfulStreak, 20)
        let intensity = usesMinimalFeedback ? 0 : CGFloat(boundedStreak) / 20
        let frequencyHz = 0.55 + Double(boundedStreak) * 0.13
        let phase = elapsedMilliseconds / 1_000 * frequencyHz * 2 * Double.pi

        for (slot, glow) in activeChannelGlows {
            let breath = CGFloat((sin(phase - Double(slot) * 0.42) + 1) * 0.5)
            glow.alpha = 0.07 + intensity * (0.12 + breath * 0.32)
        }

        let phaseCount = separatorWavePaths.count
        let phaseStep = Int((elapsedMilliseconds / 1_000 * frequencyHz * Double(phaseCount)).rounded(.down))
        for (boundary, separator) in separatorVisuals {
            let line = separator.node
            guard separator.isActive, boundedStreak >= 5, !usesMinimalFeedback, phaseCount > 0 else {
                line.path = separator.basePath
                line.position = .zero
                line.zRotation = 0
                line.setScale(1)
                line.alpha = 1
                line.lineWidth = separator.baseWidth
                continue
            }

            // Cada fase es un CGPath precalculado. Alternar esas formas evita
            // reconstruir geometría o crear nodos dentro del ciclo de render.
            let phaseIndex = ((phaseStep - boundary) % phaseCount + phaseCount) % phaseCount
            line.path = separatorWavePaths[phaseIndex]
            line.position = separator.waveOrigin
            line.zRotation = separator.waveRotation
            line.xScale = 1.8 + intensity * 4.8
            line.yScale = separator.length
            line.alpha = 0.78 + intensity * 0.22
            line.lineWidth = separator.baseWidth + intensity * 0.5
        }
    }

    private func advanceSuccessfulStreak() -> Bool {
        if successfulStreak < 999 { successfulStreak += 1 }
        refreshStreakHUD(animated: successfulStreak.isMultiple(of: 5))
        return successfulStreak.isMultiple(of: 4)
    }

    private func refreshStreakHUD(animated: Bool) {
        streakPanel?.isHidden = successfulStreak < 5
        guard successfulStreak >= 5 else { return }
        streakLabel.text = "Racha x\(successfulStreak)"
        guard animated, !usesMinimalFeedback else { return }
        streakPanel?.removeAction(forKey: "milestone")
        streakPanel?.run(.sequence([.scale(to: 1.09, duration: 0.08), .scale(to: 1, duration: 0.17)]), withKey: "milestone")
    }

    private func color(forSlot slot: Int) -> SKColor {
        guard let sound = targetSlotsBySound.first(where: { $0.value.contains(slot) })?.key
                ?? slotBySound.first(where: { $0.value == slot })?.key else { return .systemCyan }
        return color(forSound: sound)
    }

    private func color(forSound sound: String) -> SKColor {
        GameplayVisualTheme.soundAccent(sound)
    }

    func showWarmupHit(feedbackID: String = UUID().uuidString, sound: String) {
        enqueueFeedback(.init(feedbackID: feedbackID, sound: sound, judgement: nil, noteIndex: nil, offsetMilliseconds: nil, occurredAtHostTime: nil))
    }

    func showFeedback(feedbackID: String = UUID().uuidString, sound: String, judgement: RhythmJudgement, noteIndex: Int? = nil, offsetMilliseconds: Double? = nil, occurredAtHostTime: UInt64? = nil) {
        enqueueFeedback(.init(feedbackID: feedbackID, sound: sound, judgement: judgement, noteIndex: noteIndex, offsetMilliseconds: offsetMilliseconds, occurredAtHostTime: occurredAtHostTime))
    }

    private func enqueueFeedback(_ event: PracticeSceneFeedbackEvent) {
        feedbackQueueLock.lock()
        if feedbackQueueCount == feedbackQueue.count {
            feedbackQueue[feedbackQueueReadIndex] = nil
            feedbackQueueReadIndex = (feedbackQueueReadIndex + 1) % feedbackQueue.count
            feedbackQueueCount -= 1
            droppedFeedbackCount &+= 1
        }
        feedbackQueue[feedbackQueueWriteIndex] = event
        feedbackQueueWriteIndex = (feedbackQueueWriteIndex + 1) % feedbackQueue.count
        feedbackQueueCount += 1
        feedbackQueueLock.unlock()
    }

    private func drainFeedbackEvents(consumedAtHostTime: UInt64) {
        feedbackQueueLock.lock()
        let eventsToConsume = feedbackQueueCount
        feedbackQueueLock.unlock()
        guard eventsToConsume > 0 else { return }
        for _ in 0..<eventsToConsume {
            feedbackQueueLock.lock()
            guard feedbackQueueCount > 0 else {
                feedbackQueueLock.unlock()
                break
            }
            let event = feedbackQueue[feedbackQueueReadIndex]
            feedbackQueue[feedbackQueueReadIndex] = nil
            feedbackQueueReadIndex = (feedbackQueueReadIndex + 1) % feedbackQueue.count
            feedbackQueueCount -= 1
            feedbackQueueLock.unlock()

            guard let event else { continue }
            if let judgement = event.judgement {
                applyFeedback(
                    sound: event.sound,
                    judgement: judgement,
                    noteIndex: event.noteIndex,
                    offsetMilliseconds: event.offsetMilliseconds,
                    occurredAtHostTime: event.occurredAtHostTime
                )
            } else {
                applyWarmupHit(sound: event.sound)
            }
            onFeedbackConsumed?(event.feedbackID, consumedAtHostTime)
        }
    }

    private func applyWarmupHit(sound: String) {
        guard slotBySound[sound] != nil else { return }
        pulseTarget(for: sound, color: color(forSound: sound), strength: 0.45, targetSlot: nil)
        presentJudgement("SIN PUNTUAR", color: color(forSound: sound))
    }

    private func presentJudgement(_ text: String, color: SKColor) {
        let maximumWidth = max(1, min(260, size.width - 40))
        effectsRenderer.showJudgement(
            text,
            at: CGPoint(x: size.width / 2, y: 14),
            maximumWidth: maximumWidth,
            color: color,
            reducesMotion: usesMinimalFeedback
        )
    }

    private func applyFeedback(sound: String, judgement: RhythmJudgement, noteIndex: Int?, offsetMilliseconds: Double?, occurredAtHostTime: UInt64?) {
        guard let slot = noteIndex.flatMap({ slotByNoteIndex[$0] }) ?? slotBySound[sound] else { return }
        let projection = self.projection
        let hitPoint = projection.point(slot: slot, depth: 0)
        let visualAgeMilliseconds = occurredAtHostTime.map {
            AudioClock.milliseconds(from: $0, to: AudioClock.currentHostTime())
        } ?? 0
        let frameInterval = visualClockSnapshot?.frameIntervalMilliseconds ?? 0
        let arrivedAfterFrame = occurredAtHostTime != nil && visualAgeMilliseconds > max(1, frameInterval)
        let minimizesFeedback = usesMinimalFeedback
        if judgement == .extra || judgement == .miss {
            successfulStreak = 0
            refreshStreakHUD(animated: false)
            effectsRenderer.showExtra(at: hitPoint, laneWidth: projection.trackWidth(at: 0) / 16, color: GameplayVisualTheme.miss, reducesMotion: minimizesFeedback)
            presentJudgement(judgement == .extra ? "EXTRA" : "FALLO", color: GameplayVisualTheme.miss)
            return
        }
        guard let noteIndex, let note = noteByIndex[noteIndex], !consumedNoteIndices.contains(noteIndex) else { return }
        let impact = activateNoteNode(for: note)

        consumedNoteIndices.insert(note.index)
        feedbackNoteIndices.insert(note.index)
        impact.removeAllActions()
        impact.isHidden = false
        impact.zPosition = 14
        impact.alpha = 1
        let displayLeadMilliseconds = min(anticipationMilliseconds, timeline.barDurationMilliseconds * viewZoom.bars)
        let availableHeight = max(1, projection.horizonY - hitY)
        let boundedOffset = max(-95, min(95, offsetMilliseconds ?? 0))
        let impactDepth = projection.depth(for: -boundedOffset, displayLeadMilliseconds: displayLeadMilliseconds)
        let x = projection.point(slot: slot, depth: impactDepth).x
        let impactY = hitY - CGFloat(boundedOffset / max(1, displayLeadMilliseconds)) * availableHeight
        impact.position = CGPoint(x: x, y: impactY)
        let snapDuration = minimizesFeedback ? 0 : (arrivedAfterFrame ? 0.085 : 0.055)
        let snap = minimizesFeedback
            ? SKAction.move(to: CGPoint(x: x, y: hitY + 5), duration: 0)
            : SKAction.group([
                .move(to: CGPoint(x: x, y: hitY + 5), duration: snapDuration),
                .scale(to: judgement == .perfect ? 0.52 : 0.64, duration: snapDuration)
            ])
        let color = color(forSound: sound)
        let judgementColor: SKColor
        let timingSuffix: String
        if let offsetMilliseconds {
            if abs(offsetMilliseconds) < 0.5 { timingSuffix = " · A TIEMPO" }
            else { timingSuffix = String(format: " · %.0f ms %@", abs(offsetMilliseconds), offsetMilliseconds < 0 ? "ANTES" : "DESPUÉS") }
        } else { timingSuffix = "" }
        pulseTarget(for: sound, color: color, strength: judgement == .perfect ? 1 : 0.7, targetSlot: nil)
        switch judgement {
        case .perfect:
            let reachedStreakMilestone = advanceSuccessfulStreak()
            judgementColor = GameplayVisualTheme.perfect
            effectsRenderer.showImpact(at: hitPoint, color: judgementColor, particleCount: 4, reducesMotion: minimizesFeedback)
            presentJudgement("PERFECTO\(timingSuffix)", color: judgementColor)
            impact.run(feedbackAction(snap: snap, index: note.index, impact: impact, flourish: minimizesFeedback ? .wait(forDuration: 0) : .group([.scale(to: 1.42, duration: 0.13), .fadeAlpha(to: 0.95, duration: 0.13)]), exit: minimizesFeedback ? .fadeOut(withDuration: 0.24) : .group([.moveBy(x: 0, y: 54, duration: 0.34), .fadeOut(withDuration: 0.34)])))
            if reachedStreakMilestone { effectsRenderer.showStreak(at: hitPoint, color: judgementColor, reducesMotion: minimizesFeedback) }
        case .good:
            let reachedStreakMilestone = advanceSuccessfulStreak()
            judgementColor = GameplayVisualTheme.good
            effectsRenderer.showImpact(at: hitPoint, color: judgementColor, particleCount: 2, reducesMotion: minimizesFeedback)
            presentJudgement("BIEN\(timingSuffix)", color: judgementColor)
            impact.run(feedbackAction(snap: snap, index: note.index, impact: impact, flourish: minimizesFeedback ? .wait(forDuration: 0) : .group([.scale(to: 1.18, duration: 0.13), .fadeAlpha(to: 0.82, duration: 0.13)]), exit: minimizesFeedback ? .fadeOut(withDuration: 0.24) : .group([.moveBy(x: 0, y: 38, duration: 0.30), .fadeOut(withDuration: 0.30)])))
            if reachedStreakMilestone { effectsRenderer.showStreak(at: hitPoint, color: judgementColor, reducesMotion: minimizesFeedback) }
        case .regular:
            successfulStreak = 0
            refreshStreakHUD(animated: false)
            let direction: CGFloat = (offsetMilliseconds ?? 0) < 0 ? -1 : 1
            judgementColor = GameplayVisualTheme.regular
            presentJudgement("CASI\(timingSuffix)", color: judgementColor)
            impact.run(feedbackAction(snap: snap, index: note.index, impact: impact, flourish: .wait(forDuration: 0), exit: minimizesFeedback ? .fadeOut(withDuration: 0.24) : .group([.moveBy(x: direction * 35, y: 18, duration: 0.32), .fadeOut(withDuration: 0.32)])))
        case .miss, .extra:
            judgementColor = GameplayVisualTheme.miss
        }
    }

    private func pulseHitLine(isBar: Bool) {
        hitGlow?.run(.sequence([.fadeAlpha(to: isBar ? 0.38 : 0.24, duration: 0.05), .fadeAlpha(to: 0.16, duration: 0.20)]), withKey: "pulse")
        guard !usesMinimalFeedback else { return }
        hitLine?.run(.sequence([.scaleY(to: isBar ? 1.35 : 1.12, duration: 0.05), .scaleY(to: 1, duration: 0.20)]), withKey: "pulse")
    }

    private func pulseTarget(for sound: String, color: SKColor, strength: CGFloat, targetSlot: Int?) {
        guard let targets = targetBySound[sound], !targets.isEmpty else { return }
        let slots = targetSlotsBySound[sound] ?? []
        for (index, target) in targets.enumerated() {
            if let targetSlot, slots.indices.contains(index), slots[index] != targetSlot { continue }
            target.removeAction(forKey: "impact")
            let originalFill = targetBaseFills[sound].flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? target.fillColor
            let face = target.childNode(withName: "padFace") as? SKShapeNode
            face?.fillColor = color.withAlphaComponent(0.68)
            target.setScale(1)
            target.alpha = 1
            target.fillColor = color.withAlphaComponent(0.88)
            if usesMinimalFeedback {
                target.run(.sequence([.fadeAlpha(to: 1, duration: 0.05), .fadeAlpha(to: 0.98, duration: 0.16), .run { target.fillColor = originalFill; face?.fillColor = GameplayVisualTheme.padFace; target.alpha = 1 }]), withKey: "impact")
                continue
            }
            target.run(.sequence([
                .group([.scale(to: 1 + 0.12 * strength, duration: 0.06), .fadeAlpha(to: 1, duration: 0.06)]),
                .group([.scale(to: 1, duration: 0.18), .fadeAlpha(to: 0.98, duration: 0.18)]),
                .run { target.fillColor = originalFill; face?.fillColor = GameplayVisualTheme.padFace; target.alpha = 1; target.setScale(1) }
            ]), withKey: "impact")
        }
    }

    private func feedbackAction(snap: SKAction, index: Int, impact: SKShapeNode, flourish: SKAction, exit: SKAction) -> SKAction {
        .sequence([snap, flourish, exit, .run { [weak self, weak impact] in
            guard impact != nil else { return }
            self?.recycleNoteNode(at: index)
        }])
    }

}
