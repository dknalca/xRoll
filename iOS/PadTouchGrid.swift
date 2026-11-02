import SwiftUI
import UIKit
import XRollCore

/// Adaptador de la rejilla UIKit a la pantalla SwiftUI de práctica.
struct PadTouchGrid: UIViewRepresentable {
    let pads: [PadMapV2.Pad]
    let labels: [String: String]
    let maximumColumns: Int
    let onHit: (String, TimeInterval) -> Void

    func makeUIView(context: Context) -> TouchGridView {
        let view = TouchGridView()
        configure(view)
        return view
    }

    func updateUIView(_ view: TouchGridView, context: Context) {
        configure(view)
    }

    private func configure(_ view: TouchGridView) {
        view.configure(pads: pads, labels: labels, maximumColumns: maximumColumns, onHit: onHit)
    }
}

private final class TouchGridAccessibilityElement: UIAccessibilityElement {
    var activatePad: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let activatePad else { return false }
        activatePad()
        return true
    }
}

/// Presenta y recibe toques; el coordinador decide cómo reproducirlos y puntuarlos.
final class TouchGridView: UIView {
    private var pads: [PadMapV2.Pad] = []
    private var padLabels: [String: String] = [:]
    private var maximumColumns = 4
    private var grid: TouchPadGridLayout { .init(count: pads.count, maximumColumns: maximumColumns) }
    private var onHit: ((String, TimeInterval) -> Void)?
    private var accessibilityPadElements = [String: TouchGridAccessibilityElement]()
    private var lastLayoutBounds = CGRect.null

    /// SwiftUI actualiza el adaptador también al cambiar el último golpe o el
    /// estado de sesión. Solo se redibuja/reconstruye si cambió el contenido.
    func configure(pads: [PadMapV2.Pad], labels: [String: String], maximumColumns: Int,
                   onHit: @escaping (String, TimeInterval) -> Void) {
        let padsChanged = self.pads != pads
        let labelsChanged = padLabels != labels
        let columnsChanged = self.maximumColumns != maximumColumns
        self.onHit = onHit
        self.pads = pads
        padLabels = labels
        self.maximumColumns = maximumColumns
        if padsChanged { activePadTokens.removeAll() }
        if padsChanged || labelsChanged { updateAccessibilityElements() }
        else if columnsChanged { updateAccessibilityFrames() }
        if padsChanged || labelsChanged || columnsChanged { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isOpaque = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAccessibilityFrames()
        if bounds != lastLayoutBounds {
            lastLayoutBounds = bounds
            setNeedsDisplay()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let layout = grid
        for (index, pad) in pads.enumerated() {
            let frame = layout.frame(at: index, in: bounds).insetBy(dx: 3, dy: 3)
            guard frame.width > 0, frame.height > 0 else { continue }
            drawPad(pad, in: frame, context: context)
        }
    }

    private func drawPad(_ pad: PadMapV2.Pad, in frame: CGRect, context: CGContext) {
        let isActive = activePadTokens[pad.id] != nil
        let soundColor = UIColor(cgColor: GameplayVisualTheme.soundAccent(pad.sound).cgColor)
        let padColor = isActive
            ? soundColor
            : UIColor(red: 0.075, green: 0.094, blue: 0.118, alpha: 1)
        let path = UIBezierPath(roundedRect: frame, cornerRadius: min(10, frame.height * 0.12))
        context.setFillColor(padColor.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor((isActive ? UIColor.white : soundColor).withAlphaComponent(isActive ? 0.82 : 0.52).cgColor)
        context.setLineWidth(isActive ? 1.5 : 1)
        context.addPath(path.cgPath)
        context.strokePath()
        let face = UIBezierPath(roundedRect: frame.insetBy(dx: 4, dy: 4), cornerRadius: min(7, frame.height * 0.10))
        context.setFillColor(UIColor(cgColor: GameplayVisualTheme.padFace.cgColor).withAlphaComponent(isActive ? 0.42 : 1).cgColor)
        context.addPath(face.cgPath)
        context.fillPath()
        let cap = CGRect(x: frame.minX + 9, y: frame.minY + 6, width: max(2, frame.width - 18), height: 3)
        context.setFillColor(soundColor.withAlphaComponent(isActive ? 1 : 0.75).cgColor)
        context.fill(cap)

        drawSymbol(for: pad, in: frame, color: soundColor, context: context)
        drawLabel(for: pad, in: frame, isActive: isActive)
    }

    private func drawSymbol(for pad: PadMapV2.Pad, in frame: CGRect, color: UIColor, context: CGContext) {
        var symbolTransform = CGAffineTransform(translationX: frame.midX, y: frame.midY - 7)
        let symbolScale = min(1.5, max(1, min(frame.width, frame.height) / 90))
        symbolTransform = symbolTransform.scaledBy(x: symbolScale, y: symbolScale)
        let symbol = GameplayVisualTheme.padSymbolPath(for: pad.sound).copy(using: &symbolTransform)
        if let symbol {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1.6)
            context.addPath(symbol)
            context.strokePath()
        }
    }

    private func drawLabel(for pad: PadMapV2.Pad, in frame: CGRect, isActive: Bool) {
        let label = (padLabels[pad.id] ?? pad.sound.replacingOccurrences(of: "_", with: " ")).uppercased()
        let baseFontSize = min(CGFloat(18), max(CGFloat(10), frame.width / 8))
        let scaledFontSize = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: baseFontSize, compatibleWith: traitCollection)
        let fontSize = min(max(8, frame.height / 2 - 9), max(10, scaledFontSize))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.white.withAlphaComponent(isActive ? 1 : 0.88)
        ]
        (label as NSString).draw(in: CGRect(x: frame.minX + 5, y: frame.midY + 7,
            width: max(1, frame.width - 10), height: max(1, frame.height / 2 - 9)), withAttributes: attributes)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let layout = grid
        for touch in touches {
            let point = touch.location(in: self)
            guard bounds.contains(point) else { continue }
            for (index, pad) in pads.enumerated() where layout.frame(at: index, in: bounds).contains(point) {
                activate(pad, at: touch.timestamp)
                break
            }
        }
    }

    private func updateAccessibilityElements() {
        accessibilityPadElements = Dictionary(uniqueKeysWithValues: pads.map { pad in
            let element = TouchGridAccessibilityElement(accessibilityContainer: self)
            let soundName = padLabels[pad.id] ?? pad.sound.replacingOccurrences(of: "_", with: " ")
            element.accessibilityLabel = soundName
            element.accessibilityIdentifier = "practice.pad.\(pad.sound).\(pad.id)"
            element.accessibilityHint = "Toca dos veces para golpear este pad."
            element.accessibilityTraits = .button
            element.activatePad = { [weak self] in
                self?.activate(pad, at: ProcessInfo.processInfo.systemUptime)
            }
            return (pad.id, element)
        })
        accessibilityElements = pads.compactMap { accessibilityPadElements[$0.id] }
        updateAccessibilityFrames()
    }

    private func updateAccessibilityFrames() {
        let layout = grid
        for (index, pad) in pads.enumerated() {
            accessibilityPadElements[pad.id]?.accessibilityFrameInContainerSpace = layout.frame(at: index, in: bounds)
        }
    }

    private func activate(_ pad: PadMapV2.Pad, at timestamp: TimeInterval) {
        let visualToken = UUID()
        activePadTokens[pad.id] = visualToken
        setNeedsDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(110)) { [weak self] in
            guard let self, self.activePadTokens[pad.id] == visualToken else { return }
            self.activePadTokens.removeValue(forKey: pad.id)
            self.setNeedsDisplay()
        }
        onHit?(pad.id, timestamp)
    }

    private var activePadTokens = [String: UUID]()
}
