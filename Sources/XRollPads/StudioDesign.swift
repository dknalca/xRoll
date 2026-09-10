import SwiftUI

/// Visual foundation from docs/DESIGN_SYSTEM.md. Keeping these values together
/// prevents individual screens drifting into unrelated shades of blue.
enum StudioDesign {
    static let canvas = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let surface = Color(red: 0.071, green: 0.082, blue: 0.102)
    static let surfaceRaised = Color(red: 0.098, green: 0.114, blue: 0.137)
    static let surfaceHover = Color(red: 0.125, green: 0.145, blue: 0.176)
    static let textPrimary = Color(red: 0.945, green: 0.953, blue: 0.961)
    static let textSecondary = Color(red: 0.639, green: 0.671, blue: 0.710)
    static let textMuted = Color(red: 0.427, green: 0.459, blue: 0.502)
    static let accent = Color(red: 0.388, green: 0.902, blue: 0.745)
    static let leftHand = Color(red: 0, green: 0.447, blue: 0.698)
    static let rightHand = Color(red: 0.902, green: 0.624, blue: 0)
    static let regular = Color(red: 1, green: 0.831, blue: 0.231)
    static let miss = Color(red: 1, green: 0.420, blue: 0.420)
}

extension Font {
    static let studioLabel = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let studioMetric = Font.system(size: 34, weight: .bold, design: .monospaced)
    static let studioBody = Font.system(size: 14, weight: .regular)
}

struct StudioStatusPill: View {
    let title: String
    var active: Bool = true

    var body: some View {
        Label(title, systemImage: active ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.studioLabel)
            .foregroundColor(active ? StudioDesign.accent : StudioDesign.regular)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((active ? StudioDesign.accent : StudioDesign.regular).opacity(0.12))
            .clipShape(Capsule())
    }
}
