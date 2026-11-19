import SwiftUI

/// Warm, paper-like palette for the window chrome.
enum Theme {
    // Shared with the reader's Tan page color and gutter, so pages always blend into the window.
    static let backgroundRGB: PageColor.RGB = (0.945, 0.922, 0.878)
    static let panelRGB: PageColor.RGB = (0.910, 0.878, 0.827)

    static let background = Color(red: backgroundRGB.r, green: backgroundRGB.g, blue: backgroundRGB.b)
    static let panel = Color(red: panelRGB.r, green: panelRGB.g, blue: panelRGB.b)
    static let hover = Color(red: 0.878, green: 0.843, blue: 0.788)
    static let selected = Color(red: 0.847, green: 0.808, blue: 0.749)
    static let text = Color(red: 0.25, green: 0.21, blue: 0.17)
    static let secondary = Color(red: 0.49, green: 0.44, blue: 0.38)
    static let tertiary = Color(red: 0.65, green: 0.60, blue: 0.53)
    static let stroke = Color(red: 0.80, green: 0.765, blue: 0.71)
    static let accent = Color(red: 0.33, green: 0.58, blue: 0.29)

    private static let tagPalette: [Color] = [
        Color(red: 0.42, green: 0.80, blue: 0.47), // green
        Color(red: 0.84, green: 0.50, blue: 0.56), // rose
        Color(red: 0.25, green: 0.35, blue: 0.21), // forest
        Color(red: 0.42, green: 0.56, blue: 0.75), // blue
        Color(red: 0.79, green: 0.64, blue: 0.29), // ochre
        Color(red: 0.60, green: 0.50, blue: 0.72), // lavender
        Color(red: 0.37, green: 0.66, blue: 0.63), // teal
        Color(red: 0.85, green: 0.56, blue: 0.35), // orange
    ]

    /// A stable color per tag name, so tag colors need no storage.
    static func color(for tag: String) -> Color {
        // djb2: unlike String.hashValue it's the same on every launch.
        let hash = tag.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return tagPalette[Int(hash % UInt64(tagPalette.count))]
    }
}

struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(width: 32, height: 32)
            .background(Circle().fill(configuration.isPressed ? Theme.hover : Theme.background))
            .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1.5))
            .contentShape(Circle())
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(configuration.isPressed ? Theme.hover : Theme.background))
            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
            .contentShape(Capsule())
    }
}

extension View {
    /// Window chrome shared by the library and separate reader windows.
    func duckWindowStyle() -> some View {
        self
            .preferredColorScheme(.light)
            .containerBackground(Theme.background, for: .window)            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
