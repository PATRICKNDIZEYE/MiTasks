import SwiftUI
import UIKit

/// Crew's dark tokens, shared with the widget and the PWA (see DESIGN.md at
/// the repo root). miTasks is always dark, like Crew, so there is no light
/// palette: these are `renderer/style.css` `:root`, verbatim.
enum Theme {
    // MARK: Neutrals

    static let bg = Color(hex: 0x111110)
    static let surface = Color(hex: 0x161615)
    static let surface2 = Color(hex: 0x1C1C1A)
    static let surface3 = Color(hex: 0x252523)
    static let ink = Color(hex: 0xEDECE9)
    static let ink2 = Color(hex: 0xC7C5C0)
    static let muted = Color(hex: 0x8F8D88)
    static let faint = Color(hex: 0x64625E)
    static let line = Color(hex: 0x262624)
    static let lineStrong = Color(hex: 0x363532)
    static let primary = Color(hex: 0xEDECE9)
    static let primaryInk = Color(hex: 0x111110)
    /// Pressed / hover wash.
    static let hover = Color(hex: 0xFFFFFF, opacity: 0.055)
    /// Selected row or chip fill.
    static let select = Color(hex: 0xFFFFFF, opacity: 0.1)
    /// Crew's filled grey action chip ("Review", "Reply", "Focus").
    static let chipBg = Color(hex: 0x3B3B3C)
    static let chipBgHover = Color(hex: 0x474748)

    // MARK: Meaning

    static let brandDot = Color(hex: 0xF2A93B)
    /// Needs you: due today, medium priority, live.
    static let amber = Color(hex: 0xE4A53A)
    static let amberBg = Color(hex: 0x2E2414)
    /// Overdue, high priority, destructive.
    static let red = Color(hex: 0xEC6A5A)
    static let redBg = Color(hex: 0x32191A)
    /// Links and focus rings.
    static let blue = Color(hex: 0x79A3FF)
    static let blueBg = Color(hex: 0x18223A)
    /// Done, ok, free time.
    static let green = Color(hex: 0x52C48F)
    static let greenBg = Color(hex: 0x13271E)
    /// Running things: the In focus count, the lock-in pill, the focus tag.
    static let statusRunning = Color(hex: 0x72C293)
    static let focus = blue

    /// `shadow-sm`, as a colour for `.shadow(color:radius:y:)`.
    static let shadowSm = Color(hex: 0x000000, opacity: 0.4)

    // MARK: Scales

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s6: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
        static let s48: CGFloat = 48
        static let s64: CGFloat = 64
    }

    enum Radius {
        /// Chips and tags.
        static let chip: CGFloat = 4
        /// Buttons, inputs and other controls.
        static let control: CGFloat = 6
        /// Cards and rows.
        static let card: CGFloat = 8
        /// Panels, the composer and sheets.
        static let panel: CGFloat = 12
    }

    enum Height {
        static let small: CGFloat = 28
        static let regular: CGFloat = 32
        static let large: CGFloat = 40
    }

    /// The type scale: 11 · 12 · 13 · 14 · 16 · 20 · 28.
    enum Size {
        static let xs: CGFloat = 11
        static let s: CGFloat = 12
        static let m: CGFloat = 13
        static let body: CGFloat = 14
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let display: CGFloat = 28
    }

    /// Interface text in the system font. Weights stay within
    /// regular / medium / semibold.
    static func text(_ size: CGFloat = Size.body, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Times, counts and codes — Crew uses IBM Plex Mono here.
    static func mono(_ size: CGFloat = Size.s, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Screen and stat headings.
    static func display(_ size: CGFloat = Size.display, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// Makes the UIKit chrome (tab bar, navigation bars) match the page.
    static func applyChrome() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(hex: 0x111110)
        tab.shadowColor = UIColor(hex: 0x262624)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(hex: 0x8F8D88)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(hex: 0x8F8D88)]
            item.selected.iconColor = UIColor(hex: 0xEDECE9)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(hex: 0xEDECE9)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(hex: 0x161615)
        nav.shadowColor = UIColor(hex: 0x262624)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(hex: 0xEDECE9),
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Calendar and label colours arrive as "#rrggbb". These are user data and
    /// are shown as-is, never remapped.
    init?(cssHex: String?) {
        guard var s = cssHex else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// A small field title in a sheet: 12 / medium / muted.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(Theme.text(Theme.Size.s, .medium))
            .foregroundStyle(color)
    }
}

/// A tag or meta item: small muted text with an optional leading dot.
struct Chip: View {
    let text: String
    var tint: Color = Theme.muted
    var fill: Color? = nil
    var dot: Color? = nil
    var mono = false

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
                .font(mono ? Theme.mono(Theme.Size.xs) : Theme.text(Theme.Size.s))
                .monospacedDigit()
        }
        .padding(.horizontal, fill == nil ? 0 : Theme.Space.s6)
        .padding(.vertical, fill == nil ? 0 : Theme.Space.xxs)
        .foregroundStyle(tint)
        .background(fill ?? .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}

/// Crew's sidebar section head: "Needs you 4 ········ oldest first".
/// Title 13/600 ink-2, a coloured count, a 12 muted hint on the right.
struct SectionHead<Trailing: View>: View {
    let title: String
    var countText: String? = nil
    var countColor: Color = Theme.muted
    var hint: String? = nil
    var trailing: Trailing

    init(
        title: String,
        count: Int? = nil,
        countText: String? = nil,
        countColor: Color = Theme.muted,
        hint: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.countText = countText ?? count.flatMap { $0 > 0 ? "\($0)" : nil }
        self.countColor = countColor
        self.hint = hint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s6) {
            Text(title)
                .font(Theme.text(Theme.Size.m, .semibold))
                .foregroundStyle(Theme.ink2)
            if let countText {
                Text(countText)
                    .font(Theme.text(Theme.Size.m, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(countColor)
            }
            Spacer(minLength: Theme.Space.s)
            if let hint {
                Text(hint)
                    .font(Theme.text(Theme.Size.s))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            trailing
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s6)
    }
}

extension SectionHead where Trailing == EmptyView {
    init(
        title: String,
        count: Int? = nil,
        countText: String? = nil,
        countColor: Color = Theme.muted,
        hint: String? = nil
    ) {
        self.init(title: title, count: count, countText: countText, countColor: countColor, hint: hint) {
            EmptyView()
        }
    }
}

/// A label's group head inside "Up next", like a repo in Crew's mission list.
struct GroupHead: View {
    let name: String
    let color: Color?
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(color ?? Theme.faint).frame(width: 7, height: 7)
            Text(name)
                .font(Theme.text(Theme.Size.m))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(Theme.text(Theme.Size.s))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xxs)
    }
}

/// The round checkbox. `badge` puts the label's colour on its corner, like a
/// teammate's status dot in Crew.
struct CheckCircle: View {
    var done: Bool
    var size: CGFloat = 18
    var ring: Color = Theme.lineStrong
    var badge: Color? = nil

    var body: some View {
        Circle()
            .strokeBorder(done ? Theme.green : ring, lineWidth: 1.5)
            .background(Circle().fill(done ? Theme.green : .clear))
            .frame(width: size, height: size)
            .overlay {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(Theme.primaryInk)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge, !done {
                    Circle()
                        .fill(badge)
                        .frame(width: 5, height: 5)
                        .padding(2)
                        .background(Circle().fill(Theme.bg))
                        .offset(x: 4, y: 4)
                }
            }
    }
}

// MARK: - Controls

/// Crew's buttons. `.chip` is the filled grey action ("Focus", "Stop", "↑ Add");
/// `.primary` fills with ink; `.secondary` is outlined; `.quiet` has no fill.
struct CrewButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive, chip }

    var kind: Kind = .secondary
    var height: CGFloat = Theme.Height.regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.text(height >= Theme.Height.large ? Theme.Size.body : Theme.Size.s, .medium))
            .padding(.horizontal, kind == .chip ? 10 : Theme.Space.m)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(background(pressed: pressed))
            )
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.lineStrong, lineWidth: 1)
                }
            }
            .opacity(kind == .primary && pressed ? 0.85 : 1)
            .scaleEffect(kind == .chip && pressed ? 0.96 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .animation(.easeOut(duration: 0.1), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.primaryInk
        case .secondary, .chip: return Theme.ink
        case .quiet: return Theme.muted
        case .destructive: return Theme.red
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: return Theme.primary
        case .chip: return pressed ? Theme.chipBgHover : Theme.chipBg
        case .destructive: return pressed ? Theme.redBg : Theme.chipBg
        case .secondary: return pressed ? Theme.surface3 : .clear
        case .quiet: return pressed ? Theme.surface3 : .clear
        }
    }
}

extension ButtonStyle where Self == CrewButtonStyle {
    static func crew(
        _ kind: CrewButtonStyle.Kind = .secondary,
        height: CGFloat = Theme.Height.regular,
        fullWidth: Bool = false
    ) -> CrewButtonStyle {
        CrewButtonStyle(kind: kind, height: height, fullWidth: fullWidth)
    }
}

/// A square icon button in the quiet style — screen header actions, mic.
struct IconButtonLabel: View {
    let systemName: String
    var size: CGFloat = Theme.Height.regular
    var tint: Color = Theme.muted
    var fill: Color = .clear

    var body: some View {
        Image(systemName: systemName)
            .font(Theme.text(Theme.Size.body))
            .frame(width: size, height: size)
            .foregroundStyle(tint)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

/// Crew's Auto-approve pill: an outlined capsule with a small switch. On, the
/// outline and text turn the running green and a mono countdown shows.
struct PillSwitch: View {
    let on: Bool
    let title: String
    var time: String? = nil

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Capsule()
                .fill(on ? Theme.statusRunning : Theme.lineStrong)
                .frame(width: 26, height: 16)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(on ? Color(hex: 0xEAFFF3) : Theme.muted)
                        .frame(width: 12, height: 12)
                        .padding(2)
                }
            Text(title)
                .font(Theme.text(Theme.Size.s, .medium))
            if let time {
                Text(time)
                    .font(Theme.mono(Theme.Size.s, .medium))
                    .monospacedDigit()
            }
        }
        .padding(.leading, Theme.Space.s6)
        .padding(.trailing, Theme.Space.m)
        .frame(height: Theme.Height.small)
        .foregroundStyle(on ? Theme.statusRunning : Theme.muted)
        .overlay(
            Capsule().strokeBorder(on ? Theme.statusRunning.opacity(0.5) : Theme.lineStrong, lineWidth: 1)
        )
        .contentShape(Capsule())
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// Crew's input: surface fill, line-strong border, radius 6. Focus turns the
/// border blue.
private struct CrewInput: ViewModifier {
    var padding: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .padding(.horizontal, padding)
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: Theme.Height.large)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(focused ? Theme.focus : Theme.lineStrong, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    func crewInput(padding: CGFloat = Theme.Space.m) -> some View {
        modifier(CrewInput(padding: padding))
    }

    /// A Crew sheet: surface background, 12 radius, dark chrome.
    func crewSheet() -> some View {
        self
            .presentationBackground(Theme.surface)
            .presentationCornerRadius(Theme.Radius.panel)
            .preferredColorScheme(.dark)
    }
}

/// Voice and offline notices: a tinted strip with a status dot, no border.
struct StatusStrip<Trailing: View>: View {
    let tint: Color
    let fill: Color
    let title: String
    var lines = 1
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title)
                .font(Theme.text(Theme.Size.m))
                .lineLimit(lines)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.xs)
        .padding(.vertical, Theme.Space.xs)
        .frame(minHeight: Theme.Height.regular)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}
