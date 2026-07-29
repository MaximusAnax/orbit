import SwiftUI

// The Two-Rooms component library (DESIGN.md §2–§5). Law of the file:
// every component defines BOTH room forms — if a component's night form would be
// "gone", it doesn't ship (§2, the translation principle). No literal colors:
// Tokens only (D-10). No red exists anywhere in this module (D-1) — there is no
// error color to reach for, deliberately.

private struct RoomKey: EnvironmentKey {
    static let defaultValue: Room = .day
}
public extension EnvironmentValues {
    var room: Room {
        get { self[RoomKey.self] }
        set { self[RoomKey.self] = newValue }
    }
}

// MARK: - The two voices (§4)

public extension Text {
    /// Memory voice: this came from your life. Serif, never bold/italic for emphasis.
    func memoryVoice(size: CGFloat = 13.5, weight: Font.Weight = .regular) -> Text {
        font(.custom(Tokens.serifFamily, size: size).weight(weight))
    }
    /// Interface voice: the tool talking. System sans.
    func interfaceVoice(size: CGFloat = 12, weight: Font.Weight = .regular) -> Text {
        font(.system(size: size, weight: weight))
    }
}

/// §5.5: emphasis inside memory text is a 2px ember-wash underline — never bold,
/// never italic, never a fill.
public struct EmphasisUnderline: ViewModifier {
    @Environment(\.room) var room
    public func body(content: Content) -> some View {
        content.background(alignment: .bottom) {
            Rectangle().fill(Tokens.emberWash(room)).frame(height: 2).offset(y: 1)
        }
    }
}
public extension View {
    func emberEmphasis() -> some View { modifier(EmphasisUnderline()) }
}

// MARK: - The room itself

public struct RoomBackground<Content: View>: View {
    @Environment(\.colorScheme) var scheme
    let content: (Room) -> Content
    public init(@ViewBuilder content: @escaping (Room) -> Content) {
        self.content = content
    }
    public var body: some View {
        let room: Room = scheme == .dark ? .night : .day   // mode follows the system (§2)
        ZStack(alignment: .top) {
            Tokens.room(room).ignoresSafeArea()
            if room == .night { StarDust() }               // day: the same layer, empty (§5.3)
            content(room)
        }
        .environment(\.room, room)
    }
}

/// §5.3: 2–4 pinpricks, top 10% only, exactly one ember, never animated.
public struct StarDust: View {
    public init() {}
    public var body: some View {
        GeometryReader { geo in
            let h = geo.size.height * 0.10
            ZStack {
                star(.white.opacity(0.32), size: 1.4, x: 0.20, y: 0.50, in: geo.size.width, h)
                star(Tokens.ember.night.opacity(0.4), size: 1.0, x: 0.78, y: 0.70, in: geo.size.width, h)
                star(.white.opacity(0.20), size: 1.0, x: 0.55, y: 0.30, in: geo.size.width, h)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // decorative, out of the tree (§11.2)
    }
    private func star(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat,
                      in width: CGFloat, _ topBand: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
            .position(x: width * x, y: topBand * y)
    }
}

// MARK: - Paper

public struct PaperTile<Content: View>: View {
    @Environment(\.room) var room
    let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public var body: some View {
        content
            .padding(.vertical, Tokens.tilePaddingV)
            .padding(.horizontal, Tokens.tilePaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.paper(room))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
            .shadow(color: room == .day ? .black.opacity(0.06) : .clear,  // shadow is a daylight phenomenon
                    radius: room == .day ? 5 : 0, y: room == .day ? 1 : 0)
    }
}

/// The owe-sticky and every ask-card (§9: questions share the sticky's material —
/// both are things to handle by hand). Tilts by day, never at night (§5.2).
public struct NoteTile<Content: View>: View {
    @Environment(\.room) var room
    let tilted: Bool
    let content: Content
    public init(tilted: Bool = true, @ViewBuilder content: () -> Content) {
        self.tilted = tilted
        self.content = content()
    }
    public var body: some View {
        content
            .padding(.vertical, Tokens.tilePaddingV)
            .padding(.horizontal, Tokens.tilePaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.note(room))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                .strokeBorder(Tokens.noteEdge(room), lineWidth: 1))
            .rotationEffect(.degrees(room == .day && tilted ? Tokens.noteTiltDegrees : 0))
    }
}

/// Section tag: 9pt caps — bumped ink one step when rendered as text (§11.1's
/// ink-faint contrast resolution: darken, decided at build as the doc requested).
public struct SectionTag: View {
    @Environment(\.room) var room
    let text: String
    let ember: Bool
    public init(_ text: String, ember: Bool = false) {
        self.text = text
        self.ember = ember
    }
    public var body: some View {
        Text(text.uppercased())
            .interfaceVoice(size: 11, weight: .semibold)  // ≥11pt per §11.1 resolution
            .kerning(1.1)
            .foregroundStyle(ember ? Tokens.ember(room) : Tokens.inkMuted(room))
    }
}

/// §5.6: dashes separate memory items, never interface elements.
public struct DashedDivider: View {
    @Environment(\.room) var room
    public init() {}
    public var body: some View {
        Line().stroke(Tokens.paperEdge(room), style: .init(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: .init(x: 0, y: rect.midY))
            p.addLine(to: .init(x: rect.width, y: rect.midY))
            return p
        }
    }
}

/// §5.1: the flagship translation — print border by day, ember ring by night.
public struct PortraitView: View {
    @Environment(\.room) var room
    let initial: String
    let size: CGFloat
    public init(initial: String, size: CGFloat = 58) {
        self.initial = initial
        self.size = size
    }
    public var body: some View {
        Text(initial)
            .memoryVoice(size: size * 0.38, weight: .semibold)
            .foregroundStyle(Tokens.ember(room))
            .frame(width: size, height: size)
            .background(Tokens.portraitBg(room))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPortrait))
            .overlay {
                if room == .day {
                    RoundedRectangle(cornerRadius: Tokens.radiusPortrait)
                        .strokeBorder(Tokens.paper.day, lineWidth: 4)   // the print's white border
                } else {
                    RoundedRectangle(cornerRadius: Tokens.radiusPortrait)
                        .strokeBorder(Tokens.ember.night.opacity(0.4), lineWidth: 1)
                }
            }
            .shadow(color: room == .day ? .black.opacity(0.14) : Tokens.ember.night.opacity(0.13),
                    radius: room == .day ? 8 : 18, y: room == .day ? 2 : 0)
    }
}

// MARK: - Buttons: three tiers, no more (§3.6)

public struct PrimaryButton: View {
    @Environment(\.room) var room
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title).interfaceVoice(size: 13, weight: .semibold)
                .foregroundStyle(Tokens.emberInk(room))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Tokens.ember(room))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

public struct SecondaryButton: View {
    @Environment(\.room) var room
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title).interfaceVoice(size: 12.5, weight: .semibold)
                .foregroundStyle(Tokens.inkMuted(room))
                .padding(.vertical, 10).padding(.horizontal, 16)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Tokens.pillEdge(room), lineWidth: 1))
        }
    }
}

/// The pressure-free option — deferral must never feel like a downgrade (§3.6).
public struct TertiaryButton: View {
    @Environment(\.room) var room
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title).interfaceVoice(size: 12)
                .foregroundStyle(Tokens.inkFaint(room))
                .underline()
        }
        .frame(minWidth: 44, minHeight: 44)   // §11.2 touch target
    }
}

/// Mode-entry pill ("Walk me in") — not a button tier (§3.6).
public struct ModePill: View {
    @Environment(\.room) var room
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title).interfaceVoice(size: 12.5, weight: .semibold)
                .foregroundStyle(Tokens.ember(room))
                .padding(.vertical, 9).padding(.horizontal, 15)
                .background(Tokens.pillBg(room))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Tokens.pillEdge(room), lineWidth: 1))
        }
    }
}

/// §9: the hearsay chip — faint, before the claim it qualifies.
public struct HearsayChip: View {
    @Environment(\.room) var room
    let teller: String
    public init(teller: String) { self.teller = teller }
    public var body: some View {
        Text("↪ \(teller) told you this")
            .interfaceVoice(size: 11)
            .foregroundStyle(Tokens.inkFaint(room))
    }
}
