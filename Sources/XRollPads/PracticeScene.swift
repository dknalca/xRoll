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

final class PracticeScene: SKScene {
    private let timeline: ExerciseTimeline
    private let startHostTime: UInt64
    private let anticipationMilliseconds: Double
    private let slotBySound: [String: Int]
    private let soundLabels: [String: String]
    private let showsSoundLabels: Bool
    private let showsNotes: Bool
    private let emphasizesPlayerNotes: Bool
    private var gridGuide: GridGuideSubdivision
    private var viewZoom: PracticeViewZoom
    /// Nil = todas las voces son del jugador. Un conjunto permite atenuar en
    /// pantalla las voces que xRoll toca como acompañamiento.
    private let playerSounds: Set<String>?
    private var noteNodes: [(ScheduledExerciseNote, SKShapeNode)] = []
    private var pulseLines: [(timeMilliseconds: Double, node: SKShapeNode)] = []
    private let hitY: CGFloat = 82
    private let barLabel = SKLabelNode()
    private let beatLabel = SKLabelNode()
    private let progressFill = SKSpriteNode(color: .systemCyan, size: .zero)
    private var hitGlow: SKShapeNode?
    private var hitLine: SKShapeNode?
    private var targetBySound: [String: SKShapeNode] = [:]
    private var consumedNoteIndices = Set<Int>()
    private var lastPulseBeat = -1
    private var successfulStreak = 0

    init(timeline: ExerciseTimeline, startHostTime: UInt64, anticipationMilliseconds: Double, slotBySound: [String: Int], soundLabels: [String: String], showsSoundLabels: Bool = true, showsNotes: Bool = true, emphasizesPlayerNotes: Bool = false, playerSounds: Set<String>? = nil, gridGuide: GridGuideSubdivision = .eighth, viewZoom: PracticeViewZoom = .standard) {
        self.timeline = timeline
        self.startHostTime = startHostTime
        self.anticipationMilliseconds = anticipationMilliseconds
        self.slotBySound = slotBySound
        self.soundLabels = soundLabels
        self.showsSoundLabels = showsSoundLabels
        self.showsNotes = showsNotes
        self.emphasizesPlayerNotes = emphasizesPlayerNotes
        self.playerSounds = playerSounds
        self.gridGuide = gridGuide
        self.viewZoom = viewZoom
        super.init(size: CGSize(width: 960, height: 520))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.018, green: 0.035, blue: 0.085, alpha: 1)
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        let activeSlots = Set(slotBySound.values)
        let laneWidth = size.width / 16
        let background = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        background.fillColor = SKColor(red: 0.025, green: 0.055, blue: 0.13, alpha: 1)
        background.strokeColor = .clear
        addChild(background)

        // Each active sound gets its own subtly coloured runway. This makes the
        // destination of a falling note readable before the player needs to
        // identify its shape or hand.
        for index in 0..<16 {
            let x = CGFloat(index) * laneWidth
            let isActive = activeSlots.contains(index)
            let lane = SKShapeNode(rect: CGRect(x: x + 2, y: 0, width: laneWidth - 4, height: size.height))
            lane.fillColor = isActive ? color(forSlot: index).withAlphaComponent(0.10) : SKColor.white.withAlphaComponent(0.018)
            lane.strokeColor = .clear
            lane.zPosition = 0
            addChild(lane)

            let separator = SKShapeNode(rect: CGRect(x: x, y: 0, width: 1, height: size.height))
            separator.fillColor = SKColor.white.withAlphaComponent(isActive ? 0.18 : 0.06)
            separator.strokeColor = .clear
            separator.zPosition = 1
            addChild(separator)
        }
        let footer = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: hitY + 12))
        footer.fillColor = SKColor.black.withAlphaComponent(0.32)
        footer.strokeColor = .clear
        footer.zPosition = 2
        addChild(footer)

        let hitGlow = SKShapeNode(rect: CGRect(x: 0, y: hitY - 5, width: size.width, height: 10))
        hitGlow.fillColor = SKColor.systemCyan.withAlphaComponent(0.16)
        hitGlow.strokeColor = .clear
        hitGlow.zPosition = 3
        addChild(hitGlow)
        self.hitGlow = hitGlow
        let hitLine = SKShapeNode(rect: CGRect(x: 0, y: hitY - 1.5, width: size.width, height: 3))
        hitLine.fillColor = .white; hitLine.strokeColor = .clear; hitLine.glowWidth = 5; hitLine.zPosition = 4; addChild(hitLine)
        self.hitLine = hitLine

        let timingLabel = SKLabelNode(text: "GOLPEA AQUÍ")
        timingLabel.fontName = "Avenir Next Demi Bold"
        timingLabel.fontSize = 11
        timingLabel.fontColor = SKColor.white.withAlphaComponent(0.7)
        timingLabel.horizontalAlignmentMode = .left
        timingLabel.position = CGPoint(x: 12, y: hitY + 11)
        timingLabel.zPosition = 5
        addChild(timingLabel)

        // A compact transport HUD makes the repeating one-bar exercise easier
        // to follow without looking away from the falling notes.
        let hud = SKShapeNode(rectOf: CGSize(width: 180, height: 48), cornerRadius: 14)
        hud.fillColor = SKColor.black.withAlphaComponent(0.38)
        hud.strokeColor = SKColor.white.withAlphaComponent(0.16)
        hud.lineWidth = 1
        hud.position = CGPoint(x: size.width - 108, y: size.height - 34)
        hud.zPosition = 10
        addChild(hud)
        barLabel.fontName = "Avenir Next Demi Bold"
        barLabel.fontSize = 13
        barLabel.fontColor = .white
        barLabel.horizontalAlignmentMode = .left
        barLabel.position = CGPoint(x: size.width - 190, y: size.height - 30)
        barLabel.zPosition = 11
        addChild(barLabel)
        beatLabel.fontName = "Avenir Next Regular"
        beatLabel.fontSize = 11
        beatLabel.fontColor = SKColor.white.withAlphaComponent(0.7)
        beatLabel.horizontalAlignmentMode = .left
        beatLabel.position = CGPoint(x: size.width - 190, y: size.height - 46)
        beatLabel.zPosition = 11
        addChild(beatLabel)
        let progressTrack = SKSpriteNode(color: SKColor.white.withAlphaComponent(0.16), size: CGSize(width: 72, height: 4))
        progressTrack.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.position = CGPoint(x: size.width - 94, y: size.height - 39)
        progressTrack.zPosition = 11
        addChild(progressTrack)
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressFill.position = progressTrack.position
        progressFill.zPosition = 12
        addChild(progressFill)
        rebuildPulseLines()
        for (sound, slot) in slotBySound {
            let isPlayerSound = playerSounds?.contains(sound) ?? true
            let x = (CGFloat(slot) + 0.5) * laneWidth
            let target = SKShapeNode(rectOf: CGSize(width: laneWidth - 12, height: 42), cornerRadius: 9)
            target.fillColor = (isPlayerSound ? color(forSlot: slot) : .systemGray).withAlphaComponent(isPlayerSound ? 0.23 : 0.13)
            target.strokeColor = (isPlayerSound ? color(forSlot: slot) : .systemGray).withAlphaComponent(isPlayerSound ? 0.85 : 0.38)
            target.lineWidth = 1.5
            target.position = CGPoint(x: x, y: 36)
            target.zPosition = 5
            addChild(target)
            targetBySound[sound] = target

            if showsSoundLabels {
                let label = SKLabelNode(text: soundLabels[sound] ?? sound)
                label.fontName = "Avenir Next Demi Bold"
                label.fontSize = 12
                label.fontColor = SKColor.white.withAlphaComponent(isPlayerSound ? 1 : 0.42)
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                label.position = CGPoint(x: x, y: 36)
                label.zPosition = 6
                addChild(label)
            }
        }
        for note in timeline.notes {
            let node = note.hand == "L"
                ? SKShapeNode(circleOfRadius: 17)
                : SKShapeNode(rectOf: CGSize(width: 34, height: 34), cornerRadius: 7)
            let isPlayerSound = playerSounds?.contains(note.sound) ?? true
            let color: SKColor = isPlayerSound ? (emphasizesPlayerNotes ? .systemOrange : color(forSound: note.sound)) : .systemGray
            node.fillColor = color
            node.fillColor = color.withAlphaComponent(isPlayerSound ? 1 : 0.34)
            node.strokeColor = SKColor.white.withAlphaComponent(isPlayerSound ? 1 : 0.30)
            node.lineWidth = 2
            node.glowWidth = 3
            let hand = SKLabelNode(text: note.hand)
            hand.fontName = "Avenir Next Heavy"
            hand.fontSize = 13
            hand.fontColor = .black.withAlphaComponent(isPlayerSound ? 0.72 : 0.30)
            hand.verticalAlignmentMode = .center
            hand.horizontalAlignmentMode = .center
            hand.position = CGPoint(x: 0, y: -1)
            hand.zPosition = 1
            node.addChild(hand)
            node.isHidden = true
            node.zPosition = 7
            addChild(node)
            noteNodes.append((note, node))
        }
    }

    func setGridGuide(_ guide: GridGuideSubdivision) {
        guard gridGuide != guide else { return }
        gridGuide = guide
        if view != nil { rebuildPulseLines() }
    }

    func setViewZoom(_ zoom: PracticeViewZoom) {
        viewZoom = zoom
    }

    private func rebuildPulseLines() {
        pulseLines.forEach { $0.node.removeFromParent() }
        pulseLines.removeAll()

        // La pantalla siempre enseña un compás. Una frase MIDI puede contener
        // tres compases (groove → redoble → resolución), pero mostrar toda la
        // frase en la misma altura comprimiría las subdivisiones.
        let beatDuration = timeline.barDurationMilliseconds / 4
        let guidesPerBeat = gridGuide.rawValue
        let guideDuration = beatDuration / Double(guidesPerBeat)
        let finalTime = timeline.notes.map(\.timeMilliseconds).max() ?? 0
        let firstPulse = -anticipationMilliseconds
        var pulseIndex = 0
        var pulseTime = firstPulse
        while pulseTime <= finalTime + anticipationMilliseconds {
            let isBar = pulseIndex.isMultiple(of: guidesPerBeat * 4)
            let isBeat = pulseIndex.isMultiple(of: guidesPerBeat)
            let opacity: CGFloat
            if isBar { opacity = 0.55 }
            else if isBeat { opacity = 0.20 }
            else if guidesPerBeat == 2 || (guidesPerBeat >= 4 && pulseIndex.isMultiple(of: guidesPerBeat / 2)) { opacity = 0.14 }
            else if guidesPerBeat == 8 && pulseIndex.isMultiple(of: 2) { opacity = 0.10 }
            else { opacity = 0.07 }
            let line = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: isBar ? 3 : 1))
            line.fillColor = isBar ? SKColor.systemCyan.withAlphaComponent(opacity) : SKColor.white.withAlphaComponent(opacity)
            line.strokeColor = .clear
            line.zPosition = 2
            addChild(line)
            pulseLines.append((pulseTime, line))
            pulseIndex += 1
            pulseTime += guideDuration
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let now = AudioClock.milliseconds(from: startHostTime, to: AudioGetCurrentHostTime())
        let availableHeight = max(1, size.height - hitY - 18)
        let displayLeadMilliseconds = min(anticipationMilliseconds, timeline.barDurationMilliseconds * viewZoom.bars)
        let elapsed = max(0, now)
        let patternPosition = elapsed.truncatingRemainder(dividingBy: timeline.patternDurationMilliseconds)
        let barPosition = patternPosition.truncatingRemainder(dividingBy: timeline.barDurationMilliseconds)
        let beatDuration = timeline.barDurationMilliseconds / 4
        let absoluteBeat = Int(max(0, now) / beatDuration)
        if absoluteBeat != lastPulseBeat {
            lastPulseBeat = absoluteBeat
            pulseHitLine(isBar: absoluteBeat.isMultiple(of: 4))
        }
        let currentBar = min(timeline.bars, Int(patternPosition / timeline.barDurationMilliseconds) + 1)
        barLabel.text = "VUELTA \(Int(elapsed / timeline.patternDurationMilliseconds) + 1) · C \(currentBar)/\(timeline.bars)"
        beatLabel.text = "Pulso \(min(4, Int(barPosition / beatDuration) + 1)) de 4"
        progressFill.size = CGSize(width: 72 * CGFloat(barPosition / timeline.barDurationMilliseconds), height: 4)
        for (time, line) in pulseLines {
            let remaining = time - now
            line.isHidden = remaining > displayLeadMilliseconds || remaining < -120
            line.position.y = hitY + CGFloat(remaining / displayLeadMilliseconds) * availableHeight
        }
        for (note, node) in noteNodes {
            guard showsNotes else { node.isHidden = true; continue }
            guard let slot = slotBySound[note.sound] else { node.isHidden = true; continue }
            guard !consumedNoteIndices.contains(note.index) else { node.isHidden = true; continue }
            let remaining = note.timeMilliseconds - now
            node.isHidden = remaining > displayLeadMilliseconds || remaining < -120
            let x = (CGFloat(slot) + 0.5) * size.width / 16
            let y = hitY + CGFloat(remaining / displayLeadMilliseconds) * availableHeight
            node.position = CGPoint(x: x, y: y)
            let proximity = CGFloat(max(0, min(1, 1 - remaining / min(beatDuration, displayLeadMilliseconds))))
            // La nota gana presencia al acercarse: no es un marcador estático,
            // sino el objeto que el músico debe "recibir" en el punto de golpe.
            node.alpha = 0.58 + 0.42 * proximity
            node.setScale(0.78 + 0.38 * proximity)
        }
    }

    private func color(forSlot slot: Int) -> SKColor {
        guard let sound = slotBySound.first(where: { $0.value == slot })?.key else { return .systemCyan }
        return color(forSound: sound)
    }

    private func color(forSound sound: String) -> SKColor {
        switch sound {
        case "kick": return SKColor(red: 0.15, green: 0.72, blue: 1.0, alpha: 1)
        case "rim": return SKColor(red: 0.78, green: 0.59, blue: 0.25, alpha: 1)
        case "snare": return SKColor(red: 1.0, green: 0.37, blue: 0.48, alpha: 1)
        case "clap": return SKColor(red: 0.72, green: 0.48, blue: 1.0, alpha: 1)
        case "hihat_closed", "hihat_open": return SKColor(red: 0.42, green: 0.92, blue: 0.58, alpha: 1)
        case "tom_low", "tom_high": return SKColor(red: 0.18, green: 0.74, blue: 0.76, alpha: 1)
        case "crash": return SKColor(red: 1.0, green: 0.76, blue: 0.24, alpha: 1)
        case "ride": return SKColor(red: 0.92, green: 0.58, blue: 0.22, alpha: 1)
        default: return .systemCyan
        }
    }

    /// The score is already final when this runs; these actions only decorate it.
    func showFeedback(sound: String, judgement: RhythmJudgement, offsetMilliseconds: Double? = nil) {
        guard let slot = slotBySound[sound] else { return }
        if judgement == .extra || judgement == .miss {
            successfulStreak = 0
            showExtraWave(at: slot)
            return
        }
        let now = AudioClock.milliseconds(from: startHostTime, to: AudioGetCurrentHostTime())
        guard let candidate = noteNodes
            .filter({ $0.0.sound == sound && !consumedNoteIndices.contains($0.0.index) })
            .min(by: { abs($0.0.timeMilliseconds - now) < abs($1.0.timeMilliseconds - now) }),
            abs(candidate.0.timeMilliseconds - now) < 180,
            let impact = candidate.1.copy() as? SKShapeNode
        else { return }

        consumedNoteIndices.insert(candidate.0.index)
        candidate.1.isHidden = true
        impact.zPosition = 14
        impact.alpha = 1
        addChild(impact)
        let x = (CGFloat(slot) + 0.5) * size.width / 16
        let snap = SKAction.group([
            .move(to: CGPoint(x: x, y: hitY + 5), duration: 0.055),
            .scale(to: judgement == .perfect ? 0.52 : 0.64, duration: 0.055)
        ])
        let color = color(forSound: sound)
        pulseTarget(for: sound, color: color, strength: judgement == .perfect ? 1 : 0.7)
        switch judgement {
        case .perfect:
            successfulStreak += 1
            emitTrail(from: CGPoint(x: x, y: hitY + 5), color: color, count: 7)
            showHitWord("¡CLAVADO!", at: x, color: color)
            impact.run(.sequence([snap, .group([.scale(to: 1.42, duration: 0.13), .fadeAlpha(to: 0.95, duration: 0.13)]), .group([.moveBy(x: 0, y: 54, duration: 0.34), .fadeOut(withDuration: 0.34)]), .removeFromParent()]))
        case .good:
            successfulStreak += 1
            emitTrail(from: CGPoint(x: x, y: hitY + 5), color: color, count: 4)
            showHitWord("BIEN", at: x, color: color)
            impact.run(.sequence([snap, .group([.scale(to: 1.18, duration: 0.13), .fadeAlpha(to: 0.82, duration: 0.13)]), .group([.moveBy(x: 0, y: 38, duration: 0.30), .fadeOut(withDuration: 0.30)]), .removeFromParent()]))
        case .regular:
            successfulStreak = 0
            let direction: CGFloat = (offsetMilliseconds ?? 0) < 0 ? -1 : 1
            showHitWord("CASI", at: x, color: .systemYellow)
            impact.run(.sequence([snap, .group([.moveBy(x: direction * 35, y: 18, duration: 0.32), .fadeOut(withDuration: 0.32)]), .removeFromParent()]))
        case .miss, .extra: break
        }
        if successfulStreak >= 4 { successfulStreak = 0; showGrooveFlash() }
    }

    private func pulseHitLine(isBar: Bool) {
        hitGlow?.run(.sequence([.fadeAlpha(to: isBar ? 0.46 : 0.30, duration: 0.05), .fadeAlpha(to: 0.16, duration: 0.20)]), withKey: "pulse")
        hitLine?.run(.sequence([.scaleY(to: isBar ? 1.7 : 1.25, duration: 0.05), .scaleY(to: 1, duration: 0.20)]), withKey: "pulse")
    }

    private func emitTrail(from origin: CGPoint, color: SKColor, count: Int) {
        for index in 0..<count {
            let particle = SKShapeNode(circleOfRadius: CGFloat(max(3, 7 - index / 2)))
            particle.fillColor = color.withAlphaComponent(0.85)
            particle.strokeColor = .clear
            particle.position = origin
            particle.zPosition = 13
            addChild(particle)
            let lateral = CGFloat(index - count / 2) * 11
            particle.run(.sequence([.group([.moveBy(x: lateral, y: 28 + CGFloat(index * 9), duration: 0.36), .fadeOut(withDuration: 0.36)]), .removeFromParent()]))
        }
    }

    private func pulseTarget(for sound: String, color: SKColor, strength: CGFloat) {
        guard let target = targetBySound[sound] else { return }
        target.removeAction(forKey: "impact")
        let originalFill = target.fillColor
        target.fillColor = color.withAlphaComponent(0.88)
        target.run(.sequence([
            .group([.scale(to: 1 + 0.22 * strength, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08)]),
            .group([.scale(to: 1, duration: 0.34), .fadeAlpha(to: 0.95, duration: 0.34)]),
            .run { target.fillColor = originalFill }
        ]), withKey: "impact")
    }

    private func showHitWord(_ text: String, at x: CGFloat, color: SKColor) {
        let word = SKLabelNode(text: text)
        word.fontName = "Avenir Next Heavy"
        word.fontSize = 16
        word.fontColor = color
        word.horizontalAlignmentMode = .center
        word.position = CGPoint(x: x, y: hitY + 24)
        word.zPosition = 15
        word.setScale(0.72)
        addChild(word)
        word.run(.sequence([.group([.scale(to: 1.15, duration: 0.12), .moveBy(x: 0, y: 22, duration: 0.12)]), .group([.moveBy(x: 0, y: 25, duration: 0.32), .fadeOut(withDuration: 0.32)]), .removeFromParent()]))
    }

    private func showExtraWave(at slot: Int) {
        let laneWidth = size.width / 16
        let center = (CGFloat(slot) + 0.5) * laneWidth
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center - laneWidth * 0.4, y: hitY))
        path.addCurve(to: CGPoint(x: center + laneWidth * 0.4, y: hitY), control1: CGPoint(x: center - laneWidth * 0.15, y: hitY + 15), control2: CGPoint(x: center + laneWidth * 0.15, y: hitY - 15))
        let wave = SKShapeNode(path: path)
        wave.strokeColor = .systemRed
        wave.lineWidth = 3
        wave.glowWidth = 4
        wave.zPosition = 13
        addChild(wave)
        wave.run(.sequence([.group([.scaleX(to: 1.8, duration: 0.24), .fadeOut(withDuration: 0.24)]), .removeFromParent()]))
    }

    private func showGrooveFlash() {
        let flash = SKShapeNode(rect: CGRect(x: 0, y: hitY - 1, width: size.width, height: 3))
        flash.fillColor = .systemCyan.withAlphaComponent(0.85)
        flash.strokeColor = .clear
        flash.zPosition = 13
        addChild(flash)
        flash.run(.sequence([.group([.scaleX(to: 1.06, duration: 0.10), .fadeAlpha(to: 0.45, duration: 0.10)]), .fadeOut(withDuration: 0.20), .removeFromParent()]))
    }
}
