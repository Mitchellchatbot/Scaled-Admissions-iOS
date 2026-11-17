import SwiftUI

/// Tokens from docs/ui/README.md (the UI bible), named as the guide names them.
/// Light gray page, white rounded cards, one blue accent, plain words.
enum Theme {
    // Color
    static let surface = Color(hex: 0xF4F5F7)     // page background
    static let card = Color.white
    static let line = Color(hex: 0xECEEF2)
    static let rowLine = Color(hex: 0xF2F3F6)
    static let chipFlat = Color(hex: 0xF1F3F6)

    static let ink = Color(hex: 0x0F172A)
    static let ink2 = Color(hex: 0x5B6472)
    static let ink3 = Color(hex: 0x6B7480)        // the guide's ink-3-aa: safe for small text

    static let accent = Color(hex: 0x0A84FF)      // fills and icons, not small text
    static let accentText = Color(hex: 0x0A6FD6)  // blue text, primary buttons
    static let accentSoft = Color(hex: 0xE8F2FF)

    static let good = Color(hex: 0x16A34A)
    static let goodText = Color(hex: 0x15803D)
    static let goodSoft = Color(hex: 0xE6F6EC)
    static let bad = Color(hex: 0xE5484D)
    static let badText = Color(hex: 0xC93035)
    static let badSoft = Color(hex: 0xFDECED)
    static let warn = Color(hex: 0xF59E0B)
    static let warnText = Color(hex: 0xB45309)
    static let warnSoft = Color(hex: 0xFFF6E6)

    // Radius
    static let radiusTag: CGFloat = 6
    static let radiusControl: CGFloat = 10
    static let radiusBanner: CGFloat = 14
    static let radiusCard: CGFloat = 18

    // Spacing
    static let spaceItem: CGFloat = 14
    static let spaceGrid: CGFloat = 18
    static let spacePage: CGFloat = 16              // phones
}

extension Font {
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let cardTitle = Font.system(size: 17, weight: .semibold)
    static let body14 = Font.system(size: 14)
    static let rowTitle = Font.system(size: 15, weight: .semibold)
    static let label13 = Font.system(size: 13)
    static let note = Font.system(size: 12.5)
    static let tag = Font.system(size: 11, weight: .medium)
}

extension View {
    /// A white card: 18px corners, the guide's very soft shadow, no border.
    func cardStyle(padding: CGFloat = 0) -> some View {
        self
            .padding(padding)
            .background(
                // Shadow on the shape only, so it does not spill onto the card's contents.
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Theme.ink.opacity(0.05), radius: 1.5, y: 1)
            )
    }
}

/// Neutral pill: chip-flat fill, ink-2 text. Tags stay neutral (the guide's Tag).
struct TagView: View {
    let text: String
    var fill: Color = Theme.chipFlat
    var foreground: Color = Theme.ink2

    var body: some View {
        Text(text)
            .font(.tag)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radiusTag, style: .continuous))
    }
}

/// Primary button: accent-text fill, white text, weight 600.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.accentText, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
