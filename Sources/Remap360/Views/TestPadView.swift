import AppKit
import Remap360Core
import SwiftUI

/// One key press as the Mac received it, plus our best guess at where on the keymap it came from.
struct TestPadEvent: Identifiable {
    let id = UUID()
    let time = Date()
    var received: String
    var typed: String
    var source: String?
    var layer: Int?
    var position: Int?
}

/// Watches key presses while the test pad is open and swallows them so they don't trigger app shortcuts.
@MainActor
@Observable
final class TestPadMonitor {
    var events: [TestPadEvent] = []
    var heldModifiers: NSEvent.ModifierFlags = []
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored weak var model: AppModel?

    // NX_KEYTYPE_* codes for media keys arriving as system-defined events.
    private static let mediaKeys: [Int: (String, String)] = [
        0: ("C_VOL_UP", "Volume up"), 1: ("C_VOL_DN", "Volume down"), 2: ("C_BRI_UP", "Brightness up"),
        3: ("C_BRI_DN", "Brightness down"), 7: ("C_MUTE", "Mute"), 14: ("C_EJECT", "Eject"),
        16: ("C_PP", "Play / Pause"), 17: ("C_NEXT", "Next track"), 18: ("C_PREV", "Previous track"),
    ]

    func start(model: AppModel) {
        self.model = model
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .systemDefined]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                self.keyDown(event)
                return nil
            case .flagsChanged:
                self.heldModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
                return nil
            case .systemDefined where event.subtype.rawValue == 8:
                let code = (event.data1 & 0xFFFF_0000) >> 16
                let isDown = ((event.data1 & 0xFF00) >> 8) == 0xA
                if isDown, let (key, name) = Self.mediaKeys[code] { self.record(received: key, typed: name) }
                return event
            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func keyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        guard let def = Keycodes.lookup(macKeyCode: event.keyCode) else {
            record(received: "key \(event.keyCode)", typed: event.characters ?? "")
            return
        }
        var mods: [ModifierFn] = []
        let f = event.modifierFlags
        if f.contains(.control) { mods.append(.LC) }
        if f.contains(.option) { mods.append(.LA) }
        if f.contains(.shift) { mods.append(.LS) }
        if f.contains(.command) { mods.append(.LG) }
        let expr = KeyExpr(key: def.code, mods: mods)

        var typed = event.characters ?? ""
        if let shortcut = MacShortcut.match(expr.text) {
            typed = shortcut.name
        } else if typed.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) || $0.value >= 0xF700 }) {
            typed = def.name   // arrows, F-keys, return…: show the key's name
        } else if !mods.filter({ $0 != .LS && $0 != .LA }).isEmpty {
            typed = "shortcut"
        }
        record(received: expr.text, typed: typed)
    }

    private func record(received: String, typed: String) {
        let found = locate(received)
        let event = TestPadEvent(
            received: received, typed: typed,
            source: found.map { describe($0.layer, $0.position, viaHeldModifiers: $0.viaHeld) },
            layer: found?.layer, position: found?.position
        )
        events.insert(event, at: 0)
        if events.count > 60 { events.removeLast() }
    }

    /// Finds the key that most likely produced this: first an exact match (e.g. Fn+E → ⌃↑),
    /// then the bare key with modifiers held on other keys (⌥ held + Ö).
    private func locate(_ received: String) -> (layer: Int, position: Int, viaHeld: Bool)? {
        guard let model, let value = HIDUsage.encode(received) else { return nil }
        let layers = model.layers
        func search(_ target: UInt32) -> (Int, Int)? {
            for (li, layer) in layers.enumerated() {
                for (k, b) in layer.bindings.enumerated() {
                    let tap: String? = switch b.behavior {
                    case "kp": b.param(0)
                    case "mt", "lt": b.param(1)
                    default: model.context.customBehaviors[b.behavior]?.isHoldTap == true ? b.param(1) : nil
                    }
                    if let tap, HIDUsage.encode(tap) == target { return (li, k) }
                }
            }
            return nil
        }
        if let (l, k) = search(value) { return (l, k, false) }
        let bare = value & 0x00FF_FFFF
        if bare != value, let (l, k) = search(bare) { return (l, k, true) }
        return nil
    }

    private func describe(_ layer: Int, _ position: Int, viaHeldModifiers: Bool) -> String {
        guard let model, layer < model.layers.count else { return "key \(position)" }
        let ctx = model.context
        let base = model.layers[0].bindings[position].legend(in: ctx).tap
        let keyName = base.isEmpty ? "key \(position)" : base
        let prefix = layer == 0 ? "" : "\(model.layers[layer].displayName) + "
        return prefix + keyName + (viaHeldModifiers ? " (with held modifier)" : "")
    }
}

struct TestPadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var monitor = TestPadMonitor()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            let last = monitor.events.first
            ZStack {
                if model.layers.isEmpty {
                    Text("Connect your keyboard or open a config file to see where keys come from.")
                        .foregroundStyle(.secondary)
                } else {
                    KeyboardView(
                        highlighted: Set([last?.position].compactMap { $0 }),
                        interactive: false,
                        layerIndex: last?.layer ?? 0
                    )
                }
            }
            .frame(height: 250)
            .padding(.horizontal, 20)
            Divider()
            eventList
            Divider()
            footer
        }
        .frame(width: 940, height: 680)
        .onAppear { monitor.start(model: model) }
        .onDisappear { monitor.stop() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard.badge.eye")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 36, height: 36)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Pad").font(.title3.weight(.semibold))
                Text("Press keys on your keyboard to see exactly what your Mac receives.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach([(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")], id: \.1) { flag, symbol in
                    let on = monitor.heldModifiers.contains(flag)
                    Text(symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(on ? Brand.ink : .secondary)
                        .animation(.easeOut(duration: 0.1), value: on)
                }
            }
            .help("Modifiers currently held")
        }
        .padding(20)
    }

    private var eventList: some View {
        Group {
            if monitor.events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap").font(.system(size: 30)).foregroundStyle(Brand.gradient)
                    Text("Go ahead, press something").font(.headline)
                    Text("Try holding Fn and pressing your Mac row keys.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("FROM").frame(width: 260, alignment: .leading)
                            Text("MAC RECEIVED").frame(width: 200, alignment: .leading)
                            Text("RESULT").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        ForEach(Array(monitor.events.enumerated()), id: \.element.id) { i, e in
                            row(e, latest: i == 0)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ e: TestPadEvent, latest: Bool) -> some View {
        HStack {
            HStack(spacing: 8) {
                if let l = e.layer { LayerBadge(index: l, size: 18) }
                Text(e.source ?? "not in this layout")
                    .foregroundStyle(e.source == nil ? .tertiary : .primary)
            }
            .frame(width: 260, alignment: .leading)
            Text(KeyExpr(parsing: e.received).label(using: model.keyLabels))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 200, alignment: .leading)
            Text(e.typed.isEmpty ? "—" : e.typed)
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(latest ? Brand.emerald.opacity(0.10) : .clear)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("System shortcuts like Mission Control, Spotlight or your AeroSpace keys run instead of showing up here. That means they work.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { monitor.events.removeAll() }
            Button("Done") { dismiss() }
                .buttonStyle(.brand)
        }
        .padding(16)
    }
}
