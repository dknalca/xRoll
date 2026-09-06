import AudioToolbox
import SpriteKit
import XRollCore

final class PracticeScene: SKScene {
    private let timeline: ExerciseTimeline
    private let startHostTime: UInt64
    private let anticipationMilliseconds: Double
    private let slotBySound: [String: Int]
    private var noteNodes: [(ScheduledExerciseNote, SKShapeNode)] = []

    init(timeline: ExerciseTimeline, startHostTime: UInt64, anticipationMilliseconds: Double, slotBySound: [String: Int]) {
        self.timeline = timeline
        self.startHostTime = startHostTime
        self.anticipationMilliseconds = anticipationMilliseconds
        self.slotBySound = slotBySound
        super.init(size: CGSize(width: 960, height: 520))
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        let hitLine = SKShapeNode(rect: CGRect(x: 0, y: 68, width: size.width, height: 3))
        hitLine.fillColor = .white; hitLine.strokeColor = .clear; addChild(hitLine)
        for index in 0..<16 {
            let x = CGFloat(index) * size.width / 16
            let line = SKShapeNode(rect: CGRect(x: x, y: 0, width: 1, height: size.height))
            line.fillColor = SKColor(white: 0.25, alpha: 1); line.strokeColor = .clear; addChild(line)
        }
        for note in timeline.notes {
            let node = note.hand == "L"
                ? SKShapeNode(circleOfRadius: 13)
                : SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 4)
            node.fillColor = note.hand == "R" ? .orange : .systemBlue
            node.strokeColor = .white
            node.isHidden = true
            addChild(node)
            noteNodes.append((note, node))
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let now = AudioClock.milliseconds(from: startHostTime, to: AudioGetCurrentHostTime())
        let hitY: CGFloat = 70
        let availableHeight = max(1, size.height - hitY - 18)
        for (note, node) in noteNodes {
            guard let slot = slotBySound[note.sound] else { node.isHidden = true; continue }
            let remaining = note.timeMilliseconds - now
            node.isHidden = remaining > anticipationMilliseconds || remaining < -120
            let x = (CGFloat(slot) + 0.5) * size.width / 16
            let y = hitY + CGFloat(remaining / anticipationMilliseconds) * availableHeight
            node.position = CGPoint(x: x, y: y)
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
        node.position = CGPoint(x: (CGFloat(slot) + 0.5) * size.width / 16, y: 88)
        node.zPosition = 10
        addChild(node)
        node.run(.sequence([.group([.scale(to: 1.45, duration: 0.14), .fadeAlpha(to: 0.85, duration: 0.14)]), .group([.moveBy(x: 0, y: 36, duration: 0.38), .fadeOut(withDuration: 0.38)]), .removeFromParent()]))
    }
}
