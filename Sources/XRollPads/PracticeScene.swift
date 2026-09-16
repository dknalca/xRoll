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
    private let noteByIndex: [Int: ScheduledExerciseNote]
    private let slotBySound: [String: Int]
    private let soundLabels: [String: String]
    private let showsSoundLabels: Bool
    private let showsNotes: Bool
    private let emphasizesPlayerNotes: Bool
    private var gridGuide: GridGuideSubdivision
    private var viewZoom: PracticeViewZoom
    private var reducesMotion: Bool
    private var usesLowPowerVisuals: Bool
    /// Nil = todas las voces son del jugador. Un conjunto permite atenuar en
    /// pantalla las voces que xRoll toca como acompañamiento.
    private let playerSounds: Set<String>?
    private let staticLayer = SKNode()
    private var activeNoteNodes: [Int: SKShapeNode] = [:]
    private var leftNotePool = [SKShapeNode]()
    private var rightNotePool = [SKShapeNode]()
    private var activePulseLines: [Int: SKSpriteNode] = [:]
    private var pulseLinePool = [SKSpriteNode]()
    private let hitY: CGFloat = 82
    private let barLabel = SKLabelNode()
    private let beatLabel = SKLabelNode()
    private let progressFill = SKSpriteNode(color: .systemCyan, size: .zero)
    private var hitGlow: SKSpriteNode?
    private var hitLine: SKSpriteNode?
    private var targetBySound: [String: SKShapeNode] = [:]
    private var consumedNoteIndices = Set<Int>()
    private var feedbackNoteIndices = Set<Int>()
    private var lastPulseBeat = -1
    private var lastBarText = ""
    private var lastBeatText = ""
    private var successfulStreak = 0
    private var trailParticles = [SKShapeNode]()
    private var hitWords = [SKLabelNode]()
    private var extraWaves = [SKShapeNode]()
    private var grooveFlash: SKSpriteNode?

    init(timeline: ExerciseTimeline, startHostTime: UInt64, anticipationMilliseconds: Double, slotBySound: [String: Int], soundLabels: [String: String], showsSoundLabels: Bool = true, showsNotes: Bool = true, emphasizesPlayerNotes: Bool = false, playerSounds: Set<String>? = nil, gridGuide: GridGuideSubdivision = .eighth, viewZoom: PracticeViewZoom = .standard, reducesMotion: Bool = false, usesLowPowerVisuals: Bool = false) {
        self.timeline = timeline
        self.startHostTime = startHostTime
        self.anticipationMilliseconds = anticipationMilliseconds
        self.noteByIndex = Dictionary(uniqueKeysWithValues: timeline.notes.map { ($0.index, $0) })
        self.slotBySound = slotBySound
        self.soundLabels = soundLabels
        self.showsSoundLabels = showsSoundLabels
        self.showsNotes = showsNotes
        self.emphasizesPlayerNotes = emphasizesPlayerNotes
        self.playerSounds = playerSounds
        self.gridGuide = gridGuide
        self.viewZoom = viewZoom
        self.reducesMotion = reducesMotion
        self.usesLowPowerVisuals = usesLowPowerVisuals
        super.init(size: CGSize(width: 960, height: 520))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.018, green: 0.035, blue: 0.085, alpha: 1)
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        view.shouldCullNonVisibleNodes = true
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        if staticLayer.parent == nil { addChild(staticLayer) }
        rebuildStaticLayer()
        rebuildPulseLines()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard view != nil else { return }
        rebuildStaticLayer()
        for line in activePulseLines.values { line.size.width = size.width }
    }

    private func rebuildStaticLayer() {
        staticLayer.removeAllChildren()
        targetBySound.removeAll()
        let activeSlots = Set(slotBySound.values)
        let laneWidth = size.width / 16
        let background = SKSpriteNode(color: SKColor(red: 0.025, green: 0.055, blue: 0.13, alpha: 1), size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.zPosition = -2
        staticLayer.addChild(background)

        // Each active sound gets its own subtly coloured runway. This makes the
        // destination of a falling note readable before the player needs to
        // identify its shape or hand.
        for index in 0..<16 {
            let x = CGFloat(index) * laneWidth
            let isActive = activeSlots.contains(index)
            let lane = SKSpriteNode(color: isActive ? color(forSlot: index).withAlphaComponent(0.10) : SKColor.white.withAlphaComponent(0.018), size: CGSize(width: laneWidth - 4, height: size.height))
            lane.position = CGPoint(x: x + laneWidth / 2, y: size.height / 2)
            lane.zPosition = -1
            staticLayer.addChild(lane)

            let separator = SKSpriteNode(color: SKColor.white.withAlphaComponent(isActive ? 0.18 : 0.06), size: CGSize(width: 1, height: size.height))
            separator.position = CGPoint(x: x + 0.5, y: size.height / 2)
            separator.zPosition = 0
            staticLayer.addChild(separator)
        }
        let footer = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.32), size: CGSize(width: size.width, height: hitY + 12))
        footer.position = CGPoint(x: size.width / 2, y: (hitY + 12) / 2)
        footer.zPosition = 2
        staticLayer.addChild(footer)

        let hitGlow = SKSpriteNode(color: SKColor.systemCyan.withAlphaComponent(0.16), size: CGSize(width: size.width, height: 10))
        hitGlow.position = CGPoint(x: size.width / 2, y: hitY)
        hitGlow.zPosition = 3
        staticLayer.addChild(hitGlow)
        self.hitGlow = hitGlow
        let hitLine = SKSpriteNode(color: .white, size: CGSize(width: size.width, height: 3))
        hitLine.position = CGPoint(x: size.width / 2, y: hitY); hitLine.zPosition = 4; staticLayer.addChild(hitLine)
        self.hitLine = hitLine

        let timingLabel = SKLabelNode(text: "GOLPEA AQUÍ")
        timingLabel.fontName = "Avenir Next Demi Bold"
        timingLabel.fontSize = 11
        timingLabel.fontColor = SKColor.white.withAlphaComponent(0.7)
        timingLabel.horizontalAlignmentMode = .left
        timingLabel.position = CGPoint(x: 12, y: hitY + 11)
        timingLabel.zPosition = 5
        staticLayer.addChild(timingLabel)

        // A compact transport HUD makes the repeating one-bar exercise easier
        // to follow without looking away from the falling notes.
        let hud = SKShapeNode(rectOf: CGSize(width: 180, height: 48), cornerRadius: 14)
        hud.fillColor = SKColor.black.withAlphaComponent(0.38)
        hud.strokeColor = SKColor.white.withAlphaComponent(0.16)
        hud.lineWidth = 1
        hud.position = CGPoint(x: size.width - 108, y: size.height - 34)
        hud.zPosition = 10
        staticLayer.addChild(hud)
        barLabel.fontName = "Avenir Next Demi Bold"
        barLabel.fontSize = 13
        barLabel.fontColor = .white
        barLabel.horizontalAlignmentMode = .left
        barLabel.position = CGPoint(x: size.width - 190, y: size.height - 30)
        barLabel.zPosition = 11
        staticLayer.addChild(barLabel)
        beatLabel.fontName = "Avenir Next Regular"
        beatLabel.fontSize = 11
        beatLabel.fontColor = SKColor.white.withAlphaComponent(0.7)
        beatLabel.horizontalAlignmentMode = .left
        beatLabel.position = CGPoint(x: size.width - 190, y: size.height - 46)
        beatLabel.zPosition = 11
        staticLayer.addChild(beatLabel)
        let progressTrack = SKSpriteNode(color: SKColor.white.withAlphaComponent(0.16), size: CGSize(width: 72, height: 4))
        progressTrack.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.position = CGPoint(x: size.width - 94, y: size.height - 39)
        progressTrack.zPosition = 11
        staticLayer.addChild(progressTrack)
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressFill.position = progressTrack.position
        progressFill.zPosition = 12
        staticLayer.addChild(progressFill)
        for (sound, slot) in slotBySound {
            let isPlayerSound = playerSounds?.contains(sound) ?? true
            let x = (CGFloat(slot) + 0.5) * laneWidth
            let target = SKShapeNode(rectOf: CGSize(width: laneWidth - 12, height: 42), cornerRadius: 9)
            target.fillColor = (isPlayerSound ? color(forSlot: slot) : .systemGray).withAlphaComponent(isPlayerSound ? 0.23 : 0.13)
            target.strokeColor = (isPlayerSound ? color(forSlot: slot) : .systemGray).withAlphaComponent(isPlayerSound ? 0.85 : 0.38)
            target.lineWidth = 1.5
            target.position = CGPoint(x: x, y: 36)
            target.zPosition = 5
            staticLayer.addChild(target)
            targetBySound[sound] = target

            if showsSoundLabels {
                let label = SKLabelNode(text: compactSoundLabel(for: sound))
                label.fontName = "Avenir Next Demi Bold"
                label.fontSize = 12
                label.fontColor = SKColor.white.withAlphaComponent(isPlayerSound ? 1 : 0.42)
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                label.position = CGPoint(x: x, y: 36)
                label.zPosition = 6
                staticLayer.addChild(label)
            }
        }
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
        updatePulseLines(now: now, displayLeadMilliseconds: displayLeadMilliseconds, availableHeight: availableHeight)
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
            guard showsNotes else { node.isHidden = true; continue }
            let remaining = note.timeMilliseconds - now
            guard let slot = slotBySound[note.sound] else {
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
            let x = (CGFloat(slot) + 0.5) * size.width / 16
            let y = hitY + CGFloat(remaining / displayLeadMilliseconds) * availableHeight
            node.position = CGPoint(x: x, y: y)
            let proximity = CGFloat(max(0, min(1, 1 - remaining / min(beatDuration, displayLeadMilliseconds))))
            // La nota gana presencia al acercarse: no es un marcador estático,
            // sino el objeto que el músico debe "recibir" en el punto de golpe.
            node.alpha = 0.58 + 0.42 * proximity
            node.setScale(0.78 + 0.38 * proximity)
        }
        for index in notesToRecycle { recycleNoteNode(at: index) }
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
            guard !consumedNoteIndices.contains(note.index) else { continue }
            _ = activateNoteNode(for: note)
        }
    }

    private func activateNoteNode(for note: ScheduledExerciseNote) -> SKShapeNode {
        if let node = activeNoteNodes[note.index] { return node }
        let isLeft = note.hand == "L"
        let node = isLeft ? (leftNotePool.popLast() ?? makeNoteNode(isLeft: true)) : (rightNotePool.popLast() ?? makeNoteNode(isLeft: false))
        let isPlayerSound = playerSounds?.contains(note.sound) ?? true
        let color: SKColor = isPlayerSound ? (emphasizesPlayerNotes ? .systemOrange : color(forSound: note.sound)) : .systemGray
        node.removeAllActions()
        node.fillColor = color.withAlphaComponent(isPlayerSound ? 1 : 0.34)
        node.strokeColor = SKColor.white.withAlphaComponent(isPlayerSound ? 1 : 0.30)
        node.zPosition = 7
        node.alpha = 1
        node.setScale(1)
        node.isHidden = true
        if let hand = node.childNode(withName: "hand") as? SKLabelNode {
            hand.text = note.hand
            hand.fontColor = .black.withAlphaComponent(isPlayerSound ? 0.72 : 0.30)
        }
        addChild(node)
        activeNoteNodes[note.index] = node
        return node
    }

    private func makeNoteNode(isLeft: Bool) -> SKShapeNode {
        let node = isLeft ? SKShapeNode(circleOfRadius: 17) : SKShapeNode(rectOf: CGSize(width: 34, height: 34), cornerRadius: 7)
        node.lineWidth = 2
        node.zPosition = 7
        let hand = SKLabelNode()
        hand.name = "hand"
        hand.fontName = "Avenir Next Heavy"
        hand.fontSize = 13
        hand.verticalAlignmentMode = .center
        hand.horizontalAlignmentMode = .center
        hand.position = CGPoint(x: 0, y: -1)
        hand.zPosition = 1
        node.addChild(hand)
        return node
    }

    private func recycleNoteNode(at index: Int) {
        guard let node = activeNoteNodes.removeValue(forKey: index) else { return }
        node.removeAllActions()
        node.removeFromParent()
        node.isHidden = true
        feedbackNoteIndices.remove(index)
        guard let note = noteByIndex[index] else { return }
        if note.hand == "L" { leftNotePool.append(node) } else { rightNotePool.append(node) }
    }

    private func updatePulseLines(now: Double, displayLeadMilliseconds: Double, availableHeight: CGFloat) {
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
            line.position = CGPoint(x: size.width / 2, y: hitY + CGFloat((time - now) / displayLeadMilliseconds) * availableHeight)
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
        line.color = isBar ? SKColor.systemCyan.withAlphaComponent(opacity) : SKColor.white.withAlphaComponent(opacity)
        line.size = CGSize(width: size.width, height: isBar ? 3 : 1)
        line.zPosition = 2
        addChild(line)
        activePulseLines[index] = line
        return line
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

    /// El score ya es final cuando llega aquí; estas acciones solo lo representan.
    func showFeedback(sound: String, judgement: RhythmJudgement, noteIndex: Int? = nil, offsetMilliseconds: Double? = nil) {
        guard let slot = slotBySound[sound] else { return }
        if judgement == .extra || judgement == .miss {
            successfulStreak = 0
            if !usesMinimalFeedback { showExtraWave(at: slot) }
            showHitWord(judgement == .extra ? "EXTRA" : "FALLO", at: (CGFloat(slot) + 0.5) * size.width / 16, color: .systemRed)
            return
        }
        guard let noteIndex, let note = noteByIndex[noteIndex], !consumedNoteIndices.contains(noteIndex) else { return }
        let wasVisible = activeNoteNodes[noteIndex]?.isHidden == false
        let impact = activateNoteNode(for: note)

        consumedNoteIndices.insert(note.index)
        feedbackNoteIndices.insert(note.index)
        impact.removeAllActions()
        impact.isHidden = false
        impact.zPosition = 14
        impact.alpha = 1
        let x = (CGFloat(slot) + 0.5) * size.width / 16
        if !wasVisible { impact.position = CGPoint(x: x, y: hitY + 5) }
        let snap = usesMinimalFeedback
            ? SKAction.move(to: CGPoint(x: x, y: hitY + 5), duration: 0)
            : SKAction.group([
                .move(to: CGPoint(x: x, y: hitY + 5), duration: 0.055),
                .scale(to: judgement == .perfect ? 0.52 : 0.64, duration: 0.055)
            ])
        let color = color(forSound: sound)
        let timingSuffix: String
        if let offsetMilliseconds {
            if abs(offsetMilliseconds) < 0.5 { timingSuffix = " · A TIEMPO" }
            else { timingSuffix = String(format: " · %.0f ms %@", abs(offsetMilliseconds), offsetMilliseconds < 0 ? "ANTES" : "DESPUÉS") }
        } else { timingSuffix = "" }
        pulseTarget(for: sound, color: color, strength: judgement == .perfect ? 1 : 0.7)
        switch judgement {
        case .perfect:
            successfulStreak += 1
            if !usesMinimalFeedback { emitTrail(from: CGPoint(x: x, y: hitY + 5), color: color, count: 7) }
            showHitWord("¡CLAVADO!\(timingSuffix)", at: x, color: color)
            impact.run(feedbackAction(snap: snap, index: note.index, impact: impact, flourish: usesMinimalFeedback ? .wait(forDuration: 0) : .group([.scale(to: 1.42, duration: 0.13), .fadeAlpha(to: 0.95, duration: 0.13)]), exit: usesMinimalFeedback ? .fadeOut(withDuration: 0.24) : .group([.moveBy(x: 0, y: 54, duration: 0.34), .fadeOut(withDuration: 0.34)])))
        case .good:
            successfulStreak += 1
            if !usesMinimalFeedback { emitTrail(from: CGPoint(x: x, y: hitY + 5), color: color, count: 4) }
            showHitWord("BIEN\(timingSuffix)", at: x, color: color)
            impact.run(feedbackAction(snap: snap, index: note.index, impact: impact, flourish: usesMinimalFeedback ? .wait(forDuration: 0) : .group([.scale(to: 1.18, duration: 0.13), .fadeAlpha(to: 0.82, duration: 0.13)]), exit: usesMinimalFeedback ? .fadeOut(withDuration: 0.24) : .group([.moveBy(x: 0, y: 38, duration: 0.30), .fadeOut(withDuration: 0.30)])))
        case .regular:
            successfulStreak = 0
            let direction: CGFloat = (offsetMilliseconds ?? 0) < 0 ? -1 : 1
            showHitWord("CASI\(timingSuffix)", at: x, color: .systemYellow)
            impact.run(feedbackAction(snap: snap, index: note.index, impact: impact, flourish: .wait(forDuration: 0), exit: usesMinimalFeedback ? .fadeOut(withDuration: 0.24) : .group([.moveBy(x: direction * 35, y: 18, duration: 0.32), .fadeOut(withDuration: 0.32)])))
        case .miss, .extra: break
        }
        if successfulStreak >= 4 { successfulStreak = 0; if !usesMinimalFeedback { showGrooveFlash() } }
    }

    private func pulseHitLine(isBar: Bool) {
        hitGlow?.run(.sequence([.fadeAlpha(to: isBar ? 0.46 : 0.30, duration: 0.05), .fadeAlpha(to: 0.16, duration: 0.20)]), withKey: "pulse")
        guard !usesMinimalFeedback else { return }
        hitLine?.run(.sequence([.scaleY(to: isBar ? 1.7 : 1.25, duration: 0.05), .scaleY(to: 1, duration: 0.20)]), withKey: "pulse")
    }

    private func emitTrail(from origin: CGPoint, color: SKColor, count: Int) {
        for index in 0..<count {
            guard let particle = reusableTrailParticle() else { return }
            particle.removeAllActions()
            particle.fillColor = color.withAlphaComponent(0.85)
            particle.strokeColor = .clear
            particle.position = origin
            particle.zPosition = 13
            particle.alpha = 1
            particle.setScale(CGFloat(max(3, 7 - index / 2)) / 7)
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
        if usesMinimalFeedback {
            target.run(.sequence([.fadeAlpha(to: 1, duration: 0.05), .fadeAlpha(to: 0.95, duration: 0.20), .run { target.fillColor = originalFill }]), withKey: "impact")
            return
        }
        target.run(.sequence([
            .group([.scale(to: 1 + 0.22 * strength, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08)]),
            .group([.scale(to: 1, duration: 0.34), .fadeAlpha(to: 0.95, duration: 0.34)]),
            .run { target.fillColor = originalFill }
        ]), withKey: "impact")
    }

    private func showHitWord(_ text: String, at x: CGFloat, color: SKColor) {
        guard let word = reusableHitWord() else { return }
        word.removeAllActions()
        word.text = text
        word.fontColor = color
        word.position = CGPoint(x: x, y: hitY + 24)
        word.zPosition = 15
        word.alpha = 1
        word.setScale(0.72)
        addChild(word)
        if usesMinimalFeedback {
            word.run(.sequence([.fadeOut(withDuration: 0.32), .removeFromParent()]))
        } else {
            word.run(.sequence([.group([.scale(to: 1.15, duration: 0.12), .moveBy(x: 0, y: 22, duration: 0.12)]), .group([.moveBy(x: 0, y: 25, duration: 0.32), .fadeOut(withDuration: 0.32)]), .removeFromParent()]))
        }
    }

    private func showExtraWave(at slot: Int) {
        let laneWidth = size.width / 16
        let center = (CGFloat(slot) + 0.5) * laneWidth
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center - laneWidth * 0.4, y: hitY))
        path.addCurve(to: CGPoint(x: center + laneWidth * 0.4, y: hitY), control1: CGPoint(x: center - laneWidth * 0.15, y: hitY + 15), control2: CGPoint(x: center + laneWidth * 0.15, y: hitY - 15))
        guard let wave = reusableExtraWave() else { return }
        wave.removeAllActions()
        wave.path = path
        wave.strokeColor = .systemRed
        wave.lineWidth = 3
        wave.glowWidth = 4
        wave.zPosition = 13
        wave.alpha = 1
        wave.xScale = 1
        addChild(wave)
        wave.run(.sequence([.group([.scaleX(to: 1.8, duration: 0.24), .fadeOut(withDuration: 0.24)]), .removeFromParent()]))
    }

    private func showGrooveFlash() {
        let flash: SKSpriteNode
        if let grooveFlash, grooveFlash.parent == nil {
            flash = grooveFlash
        } else if grooveFlash != nil {
            return
        } else {
            let created = SKSpriteNode(color: .systemCyan, size: .zero)
            grooveFlash = created
            flash = created
        }
        flash.removeAllActions()
        flash.color = .systemCyan
        flash.colorBlendFactor = 1
        flash.size = CGSize(width: size.width, height: 3)
        flash.position = CGPoint(x: size.width / 2, y: hitY)
        flash.zPosition = 13
        flash.alpha = 0.85
        flash.xScale = 1
        addChild(flash)
        flash.run(.sequence([.group([.scaleX(to: 1.06, duration: 0.10), .fadeAlpha(to: 0.45, duration: 0.10)]), .fadeOut(withDuration: 0.20), .removeFromParent()]))
    }

    private func feedbackAction(snap: SKAction, index: Int, impact: SKShapeNode, flourish: SKAction, exit: SKAction) -> SKAction {
        .sequence([snap, flourish, exit, .run { [weak self, weak impact] in
            guard impact != nil else { return }
            self?.recycleNoteNode(at: index)
        }])
    }

    private func reusableTrailParticle() -> SKShapeNode? {
        if let particle = trailParticles.first(where: { $0.parent == nil }) { return particle }
        guard trailParticles.count < 24 else { return nil }
        let particle = SKShapeNode(circleOfRadius: 7)
        trailParticles.append(particle)
        return particle
    }

    private func reusableHitWord() -> SKLabelNode? {
        if let word = hitWords.first(where: { $0.parent == nil }) { return word }
        guard hitWords.count < 4 else { return nil }
        let word = SKLabelNode()
        word.fontName = "Avenir Next Heavy"
        word.fontSize = 16
        word.horizontalAlignmentMode = .center
        hitWords.append(word)
        return word
    }

    private func reusableExtraWave() -> SKShapeNode? {
        if let wave = extraWaves.first(where: { $0.parent == nil }) { return wave }
        guard extraWaves.count < 4 else { return nil }
        let wave = SKShapeNode()
        extraWaves.append(wave)
        return wave
    }
}
