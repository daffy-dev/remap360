import Remap360Core
import SwiftUI

struct KeyCapView: View {
    let legend: KeyLegend
    /// For transparent keys: what actually fires from a lower layer.
    var ghost: KeyLegend?
    var unit: CGFloat
    var isSelected = false
    var isHovered = false
    var isDropTarget = false
    var isHighlighted = false

    @Environment(\.colorScheme) private var scheme

    private var tint: Color? { Theme.tint(for: legend.style, layer: legend.layer) }
    private var radius: CGFloat { unit * 0.16 }

    var body: some View {
        ZStack {
            capShape
            legendContent
                .padding(.horizontal, unit * 0.07)
                .padding(.vertical, unit * 0.06)
        }
        .scaleEffect(isHovered && !isSelected ? 1.03 : 1)
        .animation(.spring(duration: 0.18), value: isHovered)
        .animation(.spring(duration: 0.22), value: isSelected)
    }

    // MARK: Cap

    @ViewBuilder private var capShape: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch legend.style {
        case .transparent:
            shape
                .fill(Color.primary.opacity(0.025))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .overlay(selectionRing(shape))
        case .none:
            shape
                .fill(Color.primary.opacity(0.04))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                .overlay(selectionRing(shape))
        default:
            shape
                .fill(surface)
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(scheme == .dark ? 0.22 : 0.14))
                    }
                }
                .overlay(
                    // top highlight for a subtle sculpted look
                    shape.inset(by: 1)
                        .stroke(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.10 : 0.9), .clear],
                                               startPoint: .top, endPoint: .center), lineWidth: 1)
                )
                .overlay(shape.strokeBorder((tint ?? .primary).opacity(tint == nil ? 0.10 : 0.45), lineWidth: 0.8))
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.12), radius: 0, x: 0, y: unit * 0.035)
                .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: unit * 0.08, y: unit * 0.05)
                .overlay(selectionRing(shape))
        }
    }

    private var surface: some ShapeStyle {
        scheme == .dark
            ? LinearGradient(colors: [Color(white: 0.25), Color(white: 0.20)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white, Color(white: 0.955)], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder private func selectionRing(_ shape: RoundedRectangle) -> some View {
        if isSelected {
            shape
                .inset(by: -unit * 0.035)
                .stroke(Brand.gradient, lineWidth: max(2, unit * 0.04))
                .shadow(color: Brand.emerald.opacity(0.65), radius: unit * 0.12)
        } else if isDropTarget || isHighlighted {
            let color = isDropTarget ? Brand.sky : Brand.amber
            shape
                .inset(by: -unit * 0.035)
                .stroke(color, lineWidth: max(2, unit * 0.035))
                .shadow(color: color.opacity(0.6), radius: unit * 0.1)
        }
    }

    // MARK: Legend

    @ViewBuilder private var legendContent: some View {
        switch legend.style {
        case .none:
            Image(systemName: "nosign")
                .font(.system(size: unit * 0.16))
                .foregroundStyle(.quaternary)
        case .transparent:
            VStack(spacing: unit * 0.02) {
                if let ghost, !ghost.tap.isEmpty {
                    Text(ghost.tap)
                        .font(.system(size: fontSize(ghost.tap) * 0.85, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: unit * 0.09))
                    .foregroundStyle(.quaternary)
            }
        case .key where legend.shifted != nil || legend.option != nil:
            ZStack {
                Text(legend.tap)
                    .font(.system(size: fontSize(legend.tap) * 0.92, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                if let shifted = legend.shifted {
                    Text(shifted)
                        .font(.system(size: unit * 0.15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .help("Shift")
                }
                if let option = legend.option {
                    Text(option)
                        .font(.system(size: unit * 0.14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.cyan.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .padding(unit * 0.02)
        default:
            VStack(spacing: unit * 0.01) {
                if let symbol = legend.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: unit * 0.13, weight: .semibold))
                        .foregroundStyle(tint ?? .secondary)
                }
                Text(legend.tap)
                    .font(.system(size: fontSize(legend.tap), weight: legend.tap.count <= 2 ? .medium : .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(legend.tap.contains(" ") ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.45)
                if let hold = legend.hold {
                    Text(hold)
                        .font(.system(size: unit * 0.115, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint ?? .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, unit * 0.04)
                        .padding(.vertical, unit * 0.01)
                        .background((tint ?? .secondary).opacity(0.14), in: Capsule())
                }
            }
        }
    }

    private func fontSize(_ text: String) -> CGFloat {
        switch text.count {
        case 0...1: unit * 0.30
        case 2: unit * 0.25
        case 3...4: unit * 0.19
        default: unit * 0.15
        }
    }
}
