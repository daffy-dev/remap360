import AppKit
import Remap360Core
import SwiftUI

/// Searchable grid of every keycode, grouped by category. Tiles can also be dragged onto the keyboard.
struct KeyPicker: View {
    @Environment(AppModel.self) private var model
    var current: String?
    var onPick: (String) -> Void
    /// Picks a whole shortcut (key + modifiers), used by the Mac section.
    var onPickShortcut: ((KeyExpr) -> Void)?

    @State private var query = ""
    @State private var category: KeyCategory? = .letters
    @State private var showMac = false

    private var results: [KeyDef] {
        if !query.isEmpty {
            let q = query.lowercased()
            let typed = Keycodes.all.filter { model.keyLabels[$0.code]?.lowercased() == q }
            return typed + Keycodes.search(query).filter { def in !typed.contains(def) }
        }
        guard let category else { return Keycodes.all }
        var list = Keycodes.all.filter { $0.category == category }
        if category == .letters {
            // Letters of the Mac's layout that live on US symbol positions (Æ, Ð, Ö, Þ on Icelandic).
            list += Keycodes.all.filter { def in
                def.category == .symbols && (model.keyLabels[def.code].map { label in
                    label.allSatisfy(\.isLetter) && !label.allSatisfy(\.isASCII)
                } ?? false)
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search keys (e.g. “enter”, “F5”, “bracket”)", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))

            if query.isEmpty {
                FlowLayout(spacing: 5) {
                    if onPickShortcut != nil {
                        Button { showMac = true; category = nil } label: {
                            Label("Mac", systemImage: "apple.logo")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(showMac ? Theme.accent : Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(showMac ? Brand.ink : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(KeyCategory.allCases) { cat in
                        Button { category = cat; showMac = false } label: {
                            Label(cat.rawValue, systemImage: cat.symbol)
                                .labelStyle(.titleOnly)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(category == cat ? Theme.accent : Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(category == cat ? Brand.ink : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if showMac && query.isEmpty, let onPickShortcut {
                VStack(spacing: 3) {
                    ForEach(MacShortcut.all) { s in
                        let on = current.map { MacShortcut.match($0) == s } ?? false
                        Button { onPickShortcut(KeyExpr(parsing: s.expr)) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: s.symbol).frame(width: 18).foregroundStyle(on ? Theme.accent : .secondary)
                                Text(s.name).font(.callout)
                                Spacer()
                                Text(KeyExpr(parsing: s.expr).label).font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(on ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.035),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .draggable("&kp \(s.expr)")
                    }
                    Text("Show Desktop is F11 (Function category). Volume, brightness and media are under Media.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 70), spacing: 6)], spacing: 6) {
                ForEach(results) { def in
                    PickerTile(def: def, label: model.keyLabels[def.code] ?? def.label,
                               isCurrent: KeyExpr(parsing: current ?? "").def?.code == def.code) { onPick(def.code) }
                }
            }
            }
            if results.isEmpty && !showMac {
                Text("No keys match “\(query)”.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding()
            }
        }
    }
}

private struct PickerTile: View {
    let def: KeyDef
    let label: String
    let isCurrent: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: label.count > 3 ? 11 : 15, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if label != def.code && label.count <= 2 && def.category != .letters && def.category != .numbers {
                    Text(def.code)
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isCurrent ? Theme.accent.opacity(0.2) : (hover ? Color.primary.opacity(0.09) : Color.primary.opacity(0.045)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label != def.label ? "Types “\(label)” on your layout  ·  \(def.code)" : "\(def.name)  ·  \(def.code)")
        .draggable("&kp \(def.code)")
    }
}

/// Captures the next key press on the Mac keyboard and maps it to a ZMK key expression.
@MainActor
@Observable
final class KeyRecorder {
    var isRecording = false
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var lastModifier: UInt16?

    func start(onCapture: @escaping (KeyExpr) -> Void) {
        stop()
        isRecording = true
        lastModifier = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                guard let def = Keycodes.lookup(macKeyCode: event.keyCode) else { return nil }
                var mods: [ModifierFn] = []
                let flags = event.modifierFlags
                if flags.contains(.control) { mods.append(.LC) }
                if flags.contains(.option) { mods.append(.LA) }
                if flags.contains(.shift) { mods.append(.LS) }
                if flags.contains(.command) { mods.append(.LG) }
                onCapture(KeyExpr(key: def.code, mods: mods))
                self.stop()
                return nil
            case .flagsChanged:
                // A modifier pressed and released on its own records the modifier itself.
                let anyDown = !event.modifierFlags.intersection([.control, .option, .shift, .command, .capsLock]).isEmpty
                if anyDown {
                    lastModifier = event.keyCode
                } else if let code = lastModifier ?? Optional(event.keyCode), let def = Keycodes.lookup(macKeyCode: code) {
                    onCapture(KeyExpr(key: def.code))
                    self.stop()
                }
                return nil
            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
