import AudioToolbox
import SpriteKit
import XRollCore

final class PracticeScene: SKScene {
    private let timeline: ExerciseTimeline
    private let startHostTime: UInt64
    private let anticipationMilliseconds: Double
    private let slotBySound: [String: Int]
    private let soundLabels: [String: String]
    private var noteNodes: [(ScheduledExerciseNote, SKShapeNode)] = []
    private var pulseLines: [(timeMilliseconds: Double, node: SKShapeNode)] = []
    private let hitY: CGFloat = 82
    private let barLabel = SKLabelNode()
    private let beatLabel = SKLabelNode()
    private let progressFill = SKSpriteNode(color: .systemCyan, size: .zero)

    init(timeline: ExerciseTimeline, startHostTime: UInt64, anticipationMilliseconds: Double, slotBySound: [String: Int], soundLabels: [String: String]) {
        self.timeline = timeline
        self.startHostTime = startHostTime
        self.anticipationMilliseconds = anticipationMilliseconds
        self.slotBySound = slotBySound
        self.soundLabels = soundLabels
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
        let hitLine = SKShapeNode(rect: CGRect(x: 0, y: hitY - 1.5, width: size.width, height: 3))
        hitLine.fillColor = .white; hitLine.strokeColor = .clear; hitLine.glowWidth = 5; hitLine.zPosition = 4; addChild(hitLine)

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
        // The falling notes use time on the vertical axis. Quarter-note guides
        // make dense eighth-note hi-hats readable; the first beat is heavier so
        // that the bar is recognisable at a glance.
        let beatDuration = timeline.patternDurationMilliseconds / 4
        let finalTime = timeline.notes.map(\.timeMilliseconds).max() ?? 0
        let firstPulse = -anticipationMilliseconds
        var pulseIndex = 0
        var pulseTime = firstPulse
        while pulseTime <= finalTime + anticipationMilliseconds {
            let isBar = pulseIndex.isMultiple(of: 4)
            let line = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: isBar ? 3 : 1))
            line.fillColor = isBar ? SKColor.systemCyan.withAlphaComponent(0.55) : SKColor.white.withAlphaComponent(0.16)
            line.strokeColor = .clear
            line.zPosition = 2
            addChild(line)
            pulseLines.append((pulseTime, line))
            pulseIndex += 1
            pulseTime += beatDuration
        }
        for (sound, slot) in slotBySound {
            let x = (CGFloat(slot) + 0.5) * laneWidth
            let target = SKShapeNode(rectOf: CGSize(width: laneWidth - 12, height: 42), cornerRadius: 9)
            target.fillColor = color(forSlot: slot).withAlphaComponent(0.23)
            target.strokeColor = color(forSlot: slot).withAlphaComponent(0.85)
            target.lineWidth = 1.5
            target.position = CGPoint(x: x, y: 36)
            target.zPosition = 5
            addChild(target)

            let label = SKLabelNode(text: soundLabels[sound] ?? sound)
            label.fontName = "Avenir Next Demi Bold"
            label.fontSize = 12
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: x, y: 36)
            label.zPosition = 6
            addChild(label)
        }
        for note in timeline.notes {
            let node = note.hand == "L"
                ? SKShapeNode(circleOfRadius: 17)
                : SKShapeNode(rectOf: CGSize(width: 34, height: 34), cornerRadius: 7)
            let color = color(forSound: note.sound)
            node.fillColor = color
            node.strokeColor = .white
            node.lineWidth = 2
            node.glowWidth = 3
            let hand = SKLabelNode(text: note.hand)
            hand.fontName = "Avenir Next Heavy"
            hand.fontSize = 13
            hand.fontColor = .black.withAlphaComponent(0.72)
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

    override func update(_ currentTime: TimeInterval) {
        let now = AudioClock.milliseconds(from: startHostTime, to: AudioGetCurrentHostTime())
        let availableHeight = max(1, size.height - hitY - 18)
        // Show one pattern at a time. With two count-in bars on screen, eighth
        // notes were only about 26 points apart and their symbols overlapped.
        let displayLeadMilliseconds = min(anticipationMilliseconds, timeline.patternDurationMilliseconds)
        let elapsed = max(0, now)
        let patternPosition = elapsed.truncatingRemainder(dividingBy: timeline.patternDurationMilliseconds)
        let beatDuration = timeline.patternDurationMilliseconds / 4
        barLabel.text = "VUELTA \(Int(elapsed / timeline.patternDurationMilliseconds) + 1)"
        beatLabel.text = "Pulso \(min(4, Int(patternPosition / beatDuration) + 1)) de 4"
        progressFill.size = CGSize(width: 72 * CGFloat(patternPosition / timeline.patternDurationMilliseconds), height: 4)
        for (time, line) in pulseLines {
            let remaining = time - now
            line.isHidden = remaining > displayLeadMilliseconds || remaining < -120
            line.position.y = hitY + CGFloat(remaining / displayLeadMilliseconds) * availableHeight
        }
        for (note, node) in noteNodes {
            guard let slot = slotBySound[note.sound] else { node.isHidden = true; continue }
            let remaining = note.timeMilliseconds - now
            node.isHidden = remaining > displayLeadMilliseconds || remaining < -120
            let x = (CGFloat(slot) + 0.5) * size.width / 16
            let y = hitY + CGFloat(remaining / displayLeadMilliseconds) * availableHeight
            node.position = CGPoint(x: x, y: y)
        }
    }

    private func color(forSlot slot: Int) -> SKColor {
        guard let sound = slotBySound.first(where: { $0.value == slot })?.key else { return .systemCyan }
        return color(forSound: sound)
    }

    private func color(forSound sound: String) -> SKColor {
        switch sound {
        case "kick": return SKColor(red: 0.15, green: 0.72, blue: 1.0, alpha: 1)
        case "snare": return SKColor(red: 1.0, green: 0.37, blue: 0.48, alpha: 1)
        case "clap": return SKColor(red: 0.72, green: 0.48, blue: 1.0, alpha: 1)
        case "hihat_closed", "hihat_open": return SKColor(red: 0.42, green: 0.92, blue: 0.58, alpha: 1)
        case "tom_low", "tom_high": return SKColor(red: 0.18, green: 0.74, blue: 0.76, alpha: 1)
        case "crash": return SKColor(red: 1.0, green: 0.76, blue: 0.24, alpha: 1)
        case "ride": return SKColor(red: 0.92, green: 0.58, blue: 0.22, alpha: 1)
        default: return .systemCyan
        }
    }

    /// Draws the player's timing result over the matching lane at the hit line.
    /// Circle: on time, triangle: regular, cross: extra/wrong hit.
    func showFeedback(sound: String, judgement: RhythmJudgement) {
        guard let slot = slotBySound[sound] else { return }
        let node: SKShapeNode
        switch judgement {
        case .perfect, .good:
            node = SKShapeNode(circleOfRadius: 18)
            node.strokeColor = .systemGreen
        case .regular:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 19)); path.addLine(to: CGPoint(x: -18, y: -14)); path.addLine(to: CGPoint(x: 18, y: -14)); path.closeSubpath()
            node = SKShapeNode(path: path)
            node.strokeColor = .systemYellow
        case .miss, .extra:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -15, y: -15)); path.addLine(to: CGPoint(x: 15, y: 15)); path.move(to: CGPoint(x: -15, y: 15)); path.addLine(to: CGPoint(x: 15, y: -15))
            node = SKShapeNode(path: path)
            node.strokeColor = .systemRed
        }
        node.lineWidth = 5
        node.fillColor = .clear
        node.position = CGPoint(x: (CGFloat(slot) + 0.5) * size.width / 16, y: hitY + 8)
        node.zPosition = 12
        addChild(node)
        node.run(.sequence([.group([.scale(to: 1.45, duration: 0.14), .fadeAlpha(to: 0.85, duration: 0.14)]), .group([.moveBy(x: 0, y: 36, duration: 0.38), .fadeOut(withDuration: 0.38)]), .removeFromParent()]))
    }
}
