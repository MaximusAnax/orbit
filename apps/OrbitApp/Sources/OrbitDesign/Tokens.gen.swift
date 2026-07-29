// GENERATED from docs/prototype/v3-mockup.html by scripts/dev/gen_tokens.py.
// DO NOT EDIT — the mockup's CSS custom properties are canonical (DESIGN.md §3, D-10).
import SwiftUI

/// One conceptual token, two lights (§2: the ember continuum et al.).
public struct RoomColor: Sendable {
    public let day: Color
    public let night: Color
    public func callAsFunction(_ room: Room) -> Color { room == .day ? day : night }
}

public enum Room: String, Sendable { case day, night }

public enum Tokens {
    public static let room = RoomColor(
        day: Color(.sRGB, red: 0.9490, green: 0.9373, blue: 0.9137, opacity: 1.000),
        night: Color(.sRGB, red: 0.0627, green: 0.0784, blue: 0.1373, opacity: 1.000))
    public static let paper = RoomColor(
        day: Color(.sRGB, red: 1.0000, green: 0.9922, blue: 0.9765, opacity: 1.000),
        night: Color(.sRGB, red: 1.0000, green: 1.0000, blue: 1.0000, opacity: 0.042))
    public static let paperEdge = RoomColor(
        day: Color(.sRGB, red: 0.9059, green: 0.8745, blue: 0.8235, opacity: 1.000),
        night: Color(.sRGB, red: 0.6275, green: 0.6863, blue: 0.8431, opacity: 0.150))
    public static let note = RoomColor(
        day: Color(.sRGB, red: 0.9725, green: 0.9333, blue: 0.7961, opacity: 1.000),
        night: Color(.sRGB, red: 0.9020, green: 0.6980, blue: 0.4510, opacity: 0.090))
    public static let noteEdge = RoomColor(
        day: Color(.sRGB, red: 0.9176, green: 0.8627, blue: 0.6824, opacity: 1.000),
        night: Color(.sRGB, red: 0.9020, green: 0.6980, blue: 0.4510, opacity: 0.280))
    public static let ink = RoomColor(
        day: Color(.sRGB, red: 0.1608, green: 0.1451, blue: 0.1255, opacity: 1.000),
        night: Color(.sRGB, red: 0.8706, green: 0.8902, blue: 0.9412, opacity: 1.000))
    public static let inkMuted = RoomColor(
        day: Color(.sRGB, red: 0.4235, green: 0.3961, blue: 0.3529, opacity: 1.000),
        night: Color(.sRGB, red: 0.5608, green: 0.6039, blue: 0.7255, opacity: 1.000))
    public static let inkFaint = RoomColor(
        day: Color(.sRGB, red: 0.5961, green: 0.5647, blue: 0.5137, opacity: 1.000),
        night: Color(.sRGB, red: 0.4078, green: 0.4549, blue: 0.6039, opacity: 1.000))
    public static let ember = RoomColor(
        day: Color(.sRGB, red: 0.5412, green: 0.3725, blue: 0.2118, opacity: 1.000),
        night: Color(.sRGB, red: 0.9020, green: 0.6980, blue: 0.4510, opacity: 1.000))
    public static let emberWash = RoomColor(
        day: Color(.sRGB, red: 0.9255, green: 0.8510, blue: 0.7059, opacity: 1.000),
        night: Color(.sRGB, red: 0.9020, green: 0.6980, blue: 0.4510, opacity: 0.420))
    public static let emberInk = RoomColor(
        day: Color(.sRGB, red: 1.0000, green: 0.9922, blue: 0.9765, opacity: 1.000),
        night: Color(.sRGB, red: 0.1255, green: 0.0902, blue: 0.0353, opacity: 1.000))
    public static let noteInk = RoomColor(
        day: Color(.sRGB, red: 0.1608, green: 0.1451, blue: 0.1255, opacity: 1.000),
        night: Color(.sRGB, red: 0.8706, green: 0.8902, blue: 0.9412, opacity: 1.000))
    public static let portraitBg = RoomColor(
        day: Color(.sRGB, red: 0.8667, green: 0.8275, blue: 0.7608, opacity: 1.000),
        night: Color(.sRGB, red: 0.1176, green: 0.1451, blue: 0.2510, opacity: 1.000))
    public static let pillBg = RoomColor(
        day: Color(.sRGB, red: 1.0000, green: 0.9922, blue: 0.9765, opacity: 1.000),
        night: Color(.sRGB, red: 1.0000, green: 1.0000, blue: 1.0000, opacity: 0.050))
    public static let pillEdge = RoomColor(
        day: Color(.sRGB, red: 0.8863, green: 0.8510, blue: 0.7882, opacity: 1.000),
        night: Color(.sRGB, red: 0.6275, green: 0.6863, blue: 0.8431, opacity: 0.200))

    // Geometry constants (DESIGN.md §3.5) — from the mockup's --radius-* and layout CSS.
    public static let radiusCard: CGFloat = 13
    public static let radiusPortrait: CGFloat = 12
    public static let radiusPill: CGFloat = 22
    public static let screenPaddingTop: CGFloat = 24
    public static let screenPaddingSide: CGFloat = 16
    public static let gridGap: CGFloat = 9
    public static let tilePaddingV: CGFloat = 13
    public static let tilePaddingH: CGFloat = 14
    public static let noteTiltDegrees: Double = 0.4   // day only; nothing tilts in the sky

    // The two voices (§4): serif = memory, sans = interface.
    public static let serifFamily = "Iowan Old Style"
}
