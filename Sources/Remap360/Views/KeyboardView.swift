import Remap360Core
import SwiftUI

/// Drag payload prefix used when dragging a key onto another key (swap).
let keyDragPrefix = "remap360-key:"

/// The full Adv360 drawn from its physical layout, with interactive keycaps.
struct KeyboardView: View {
    @Environment(AppModel.self) private var model
    var highlighted: Set<Int> = []
    var interactive = true
    /// Draw this layer instead of the selected one (used for non-interactive previews).
    var layerIndex: Int?
    /// Draw plain caps with these legends instead of a layer (used for "press these keys" guides).
    var labels: [Int: String]?
    @State private var dropTarget: Int?

    var body: some View {
        GeometryReader { geo in
            let bounds = Adv360Layout.bounds
            let pad: CGFloat = 30
            let scale = min((geo.size.width - pad * 2) / bounds.width, (geo.size.height - pad * 2) / bounds.height)
            let unit = 100 * scale
            let originX = (geo.size.width - bounds.width * scale) / 2 - bounds.minX * scale
            let originY = (geo.size.height - bounds.height * scale) / 2 - bounds.minY * scale

            ZStack(alignment: .topLeading) {
                CaseShape(scale: scale, origin: CGPoint(x: originX, y: originY))

                if let labels {
                    ForEach(Adv360Layout.keys, id: \.index) { key in
                        let center = key.center
                        let text = labels[key.index]
                        KeyCapView(legend: KeyLegend(tap: text ?? "", style: text == nil ? .none : .key),
                                   unit: unit, isHighlighted: highlighted.contains(key.index))
                            .opacity(text == nil ? 0.6 : 1)
                            .frame(width: key.w * scale - unit * 0.07, height: key.h * scale - unit * 0.07)
                            .rotationEffect(.degrees(key.degrees))
                            .position(x: originX + center.x * scale, y: originY + center.y * scale)
                    }
                } else if let li = layerIndex ?? model.selectedLayerIndex, li < model.layers.count {
                    let layer = model.layers[li]
                    let ctx = model.context
                    ForEach(Adv360Layout.keys, id: \.index) { key in
                        let binding = key.index < layer.bindings.count ? layer.bindings[key.index] : .none
                        let ghost = binding == .trans ? model.effectiveBinding(layer: li, key: key.index)?.legend(in: ctx) : nil
                        let center = key.center
                        cap(key: key, binding: binding, ghost: ghost, unit: unit, ctx: ctx)
                            .frame(width: key.w * scale - unit * 0.07, height: key.h * scale - unit * 0.07)
                            .rotationEffect(.degrees(key.degrees))
                            .position(x: originX + center.x * scale, y: originY + center.y * scale)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cap(key: PhysicalKey, binding: KeyBinding, ghost: KeyLegend?, unit: CGFloat, ctx: BindingContext) -> some View {
        let i = key.index
        let view = KeyCapView(
            legend: binding.legend(in: ctx),
            ghost: ghost,
            unit: unit,
            isSelected: interactive && model.selectedKey == i,
            isHovered: interactive && model.hoveredKey == i,
            isDropTarget: dropTarget == i,
            isHighlighted: highlighted.contains(i)
        )
        if interactive {
            view
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { model.hoveredKey = i } else if model.hoveredKey == i { model.hoveredKey = nil }
                }
                .onTapGesture { model.selectedKey = i }
                .help(binding.describe(in: ctx))
                .draggable(keyDragPrefix + String(i)) {
                    KeyCapView(legend: binding.legend(in: ctx), unit: unit, isSelected: true)
                        .frame(width: key.w / 100 * unit, height: key.h / 100 * unit)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let item = items.first else { return false }
                    if item.hasPrefix(keyDragPrefix), let from = Int(item.dropFirst(keyDragPrefix.count)) {
                        model.swapKeys(from, i)
                    } else {
                        let parsed = BindingParser.parse(item)
                        guard parsed.count == 1 else { return false }
                        model.setBinding(parsed[0], at: i, name: "Drop Key")
                    }
                    model.selectedKey = i
                    return true
                } isTargeted: { targeted in
                    if targeted { dropTarget = i } else if dropTarget == i { dropTarget = nil }
                }
        } else {
            view
        }
    }
}

/// Soft silhouette of both halves, made from the union of padded key rectangles.
private struct CaseShape: View {
    let scale: CGFloat
    let origin: CGPoint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, _ in
            for left in [true, false] {
                var path = Path()
                for key in Adv360Layout.keys where key.isLeft == left {
                    let c = key.center
                    let pad: CGFloat = 26
                    let rect = CGRect(x: -(key.w / 2 + pad), y: -(key.h / 2 + pad), width: key.w + pad * 2, height: key.h + pad * 2)
                    let transform = CGAffineTransform(translationX: origin.x + c.x * scale, y: origin.y + c.y * scale)
                        .scaledBy(x: scale, y: scale)
                        .rotated(by: key.degrees * .pi / 180)
                    path.addPath(Path(roundedRect: rect, cornerRadius: 46), transform: transform)
                }
                let fill = scheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.045)
                ctx.fill(path, with: .color(fill))
            }
        }
        .allowsHitTesting(false)
    }
}
