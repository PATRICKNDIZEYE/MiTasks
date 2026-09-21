import SwiftUI

/// The widget's palette, carried over so the phone and the desk feel like
/// one product. Hex values match renderer/style.css.
enum Theme {
    static let bgHi = Color(hex: 0x201D18)
    static let bgLo = Color(hex: 0x141210)
    static let ink = Color(hex: 0xF0EADD)
    static let ink2 = Color(hex: 0xF0EADD).opacity(0.56)
    static let ink3 = Color(hex: 0xF0EADD).opacity(0.30)
    static let hair = Color(hex: 0xF0EADD).opacity(0.09)
    static let amber = Color(hex: 0xD9A441)
    static let amberSoft = Color(hex: 0xD9A441).opacity(0.14)
    static let clay = Color(hex: 0xC96F5A)
    static let sage = Color(hex: 0x8FA876)

    static let background = LinearGradient(
        colors: [bgHi, bgLo],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Fraunces isn't bundled, but its serif weight is the whole point of the
    /// widget's headings — the system serif carries the same feeling.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .bold)
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

    /// Calendar colours arrive from EventKit as "#rrggbb".
    init?(cssHex: String?) {
        guard var s = cssHex else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// An uppercase, letter-spaced caption — the widget uses this for every
/// section header and date line.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.ink3

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label())
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// A small pill used for labels, priorities, dates and age.
struct Chip: View {
    let text: String
    var tint: Color = Theme.ink2
    var fill: Color = Theme.ink.opacity(0.07)
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let dot {
                Circle().fill(dot).frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .foregroundStyle(tint)
        .background(fill, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SectionRule: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Eyebrow(text: title)
            Rectangle().fill(Theme.hair).frame(height: 1)
            if let trailing { trailing }
        }
        .padding(.top, 26)
        .padding(.bottom, 2)
    }
}
