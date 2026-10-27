import SwiftUI

// Self-contained (SwiftUI only) so scripts/make-icon.swift can compile it to render the app icon.

/// "Aurora": deep teal-black ink, electric cyan → emerald → lime, with amber and sky accents.
enum Brand {
    static let ink = Color(red: 0.027, green: 0.075, blue: 0.094)      // #071318
    static let night = Color(red: 0.043, green: 0.145, blue: 0.188)    // #0B2530
    static let cyan = Color(red: 0.133, green: 0.827, blue: 0.933)     // #22D3EE
    static let emerald = Color(red: 0.063, green: 0.851, blue: 0.627)  // #10D9A0
    static let lime = Color(red: 0.714, green: 0.953, blue: 0.361)     // #B6F35C
    static let amber = Color(red: 1.000, green: 0.710, blue: 0.278)    // #FFB547
    static let sky = Color(red: 0.353, green: 0.722, blue: 1.000)      // #5AB8FF
    static let violet = Color(red: 0.655, green: 0.545, blue: 0.980)   // #A78BFA
    static let rose = Color(red: 0.984, green: 0.443, blue: 0.522)     // #FB7185

    static let gradientColors = [cyan, emerald, lime]
    static let gradient = LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    static let horizontal = LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
}

/// The Remap360 mark: a 360° ring ending in an arrow, around two tilted keycaps (the split halves),
/// one of which glows because it has been remapped.
struct LogoMark: View {
    var monochrome = false

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            ctx.translateBy(x: (size.width - s) / 2, y: (size.height - s) / 2)
            ctx.scaleBy(x: s, y: s)

            let center = CGPoint(x: 0.5, y: 0.5)
            let radius = 0.36
            let line = 0.088
            let start = -18.0, end = 278.0   // degrees, clockwise (y points down)

            // Ring
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
            let ringShading: GraphicsContext.Shading = monochrome
                ? .color(.white)
                : .conicGradient(Gradient(colors: [Brand.lime, Brand.emerald, Brand.cyan, Brand.cyan]),
                                 center: center, angle: .degrees(start - 10))
            ctx.stroke(ring, with: ringShading, style: StrokeStyle(lineWidth: line, lineCap: .round))

            // Arrowhead at the end of the ring, pointing along the clockwise tangent.
            let a = end * .pi / 180
            let tip = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            let tangent = CGPoint(x: -sin(a), y: cos(a))
            let normal = CGPoint(x: cos(a), y: sin(a))
            let head = 0.135, half = 0.098
            var arrow = Path()
            arrow.move(to: CGPoint(x: tip.x + tangent.x * head, y: tip.y + tangent.y * head))
            arrow.addLine(to: CGPoint(x: tip.x + normal.x * half - tangent.x * 0.01, y: tip.y + normal.y * half - tangent.y * 0.01))
            arrow.addLine(to: CGPoint(x: tip.x - normal.x * half - tangent.x * 0.01, y: tip.y - normal.y * half - tangent.y * 0.01))
            arrow.closeSubpath()
            ctx.fill(arrow, with: monochrome ? .color(.white) : .color(Brand.cyan))

            // Keycaps
            func keycap(cx: Double, cy: Double, angle: Double, fill: GraphicsContext.Shading, glow: Bool) {
                var k = ctx
                k.translateBy(x: cx, y: cy)
                k.rotate(by: .degrees(angle))
                let size = 0.215
                let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
                let cap = Path(roundedRect: rect, cornerRadius: 0.05, style: .continuous)
                if glow && !monochrome {
                    var g = k
                    g.addFilter(.blur(radius: 0.04))
                    g.fill(cap, with: .color(Brand.emerald.opacity(0.9)))
                }
                k.fill(cap, with: fill)
                // top face highlight
                let face = Path(roundedRect: rect.insetBy(dx: 0.028, dy: 0.028).offsetBy(dx: 0, dy: -0.012),
                                cornerRadius: 0.032, style: .continuous)
                k.fill(face, with: .color(.white.opacity(glow ? 0.18 : 0.55)))
            }
            keycap(cx: 0.375, cy: 0.515, angle: -12, fill: .color(.white.opacity(0.94)), glow: false)
            keycap(cx: 0.625, cy: 0.515, angle: 12,
                   fill: monochrome ? .color(.white.opacity(0.6))
                       : .linearGradient(Gradient(colors: [Brand.emerald, Brand.lime]),
                                         startPoint: CGPoint(x: -0.1, y: -0.1), endPoint: CGPoint(x: 0.1, y: 0.1)),
                   glow: true)
        }
    }
}

/// Mark + "Remap360" wordmark.
struct Wordmark: View {
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: height * 0.28) {
            LogoMark().frame(width: height, height: height)
            HStack(spacing: 0) {
                Text("Remap").foregroundStyle(.primary.opacity(0.95))
                Text("360").foregroundStyle(Brand.horizontal)
            }
            .font(.system(size: height * 0.62, weight: .heavy, design: .rounded))
            .tracking(-height * 0.012)
            .lineLimit(1)
            .fixedSize()
        }
    }
}

/// The full macOS app icon artwork, drawn on a 1024×1024 canvas.
struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Brand.night, Brand.ink], startPoint: .top, endPoint: .bottom))
                .overlay {
                    ZStack {
                        RadialGradient(colors: [Brand.cyan.opacity(0.40), .clear], center: UnitPoint(x: 0.25, y: 0.2),
                                       startRadius: 0, endRadius: 520)
                        RadialGradient(colors: [Brand.lime.opacity(0.22), .clear], center: UnitPoint(x: 0.9, y: 1.0),
                                       startRadius: 0, endRadius: 520)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

            LogoMark()
                .frame(width: 600, height: 600)
                .shadow(color: Brand.emerald.opacity(0.45), radius: 40)
        }
        .frame(width: 1024, height: 1024)
    }
}
