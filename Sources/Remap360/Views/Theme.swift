import Remap360Core
import SwiftUI

enum Theme {
    static let accent = Brand.cyan

    /// The Adv360 Pro shows the active layer on its indicator LEDs; mirror those colors.
    /// Index 0 is "off" on the keyboard; we use a neutral slate for it.
    static func layerColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.45, green: 0.50, blue: 0.58),   // 0 off
            Color(red: 0.72, green: 0.74, blue: 0.80),   // 1 white
            Color(red: 0.24, green: 0.48, blue: 1.00),   // 2 blue
            Color(red: 0.20, green: 0.78, blue: 0.42),   // 3 green
            Color(red: 1.00, green: 0.30, blue: 0.32),   // 4 red
            Color(red: 0.80, green: 0.32, blue: 0.95),   // 5 magenta
            Color(red: 0.10, green: 0.78, blue: 0.86),   // 6 cyan
            Color(red: 1.00, green: 0.78, blue: 0.10),   // 7 yellow
        ]
        if index < palette.count { return palette[index] }
        // Above 7 the right LED cycles blue, green, red, magenta, cyan, yellow, white.
        return palette[[2, 3, 4, 5, 6, 7, 1][(index - 8) % 7]]
    }

    static func layerLEDName(_ index: Int) -> String {
        let names = ["Off", "White", "Blue", "Green", "Red", "Magenta", "Cyan", "Yellow"]
        return index < names.count ? names[index] : "Mixed"
    }

    static func tint(for style: KeyLegend.Style, layer: Int?) -> Color? {
        switch style {
        case .key, .transparent, .none: nil
        case .modifier: Brand.cyan
        // One colour per kind of key so they're easy to tell apart; layer badges keep the LED colours.
        case .layer: Brand.violet
        case .holdTap: Brand.amber
        case .system: Brand.rose
        case .macro: Brand.lime
        case .unknown: Color.gray
        }
    }

    static func styleName(_ style: KeyLegend.Style) -> String {
        switch style {
        case .key: "Key"
        case .modifier: "Modifier"
        case .layer: "Layer"
        case .holdTap: "Hold-tap"
        case .system: "Device"
        case .macro: "Macro"
        case .transparent: "Transparent"
        case .none: "Disabled"
        case .unknown: "Custom"
        }
    }
}

extension View {
    func cardBackground(radius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.background.secondary)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
    }
}

/// Small colored capsule showing a layer's index and LED color.
struct LayerBadge: View {
    let index: Int
    var size: CGFloat = 22

    var body: some View {
        Text("\(index)")
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(index == 1 || index == 7 ? Color.black.opacity(0.75) : .white)
            .frame(width: size, height: size)
            .background(Theme.layerColor(index).gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Primary call-to-action: brand gradient capsule.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Brand.horizontal, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: Brand.emerald.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 8, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var brand: GradientButtonStyle { GradientButtonStyle() }
}
