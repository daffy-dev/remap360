import Remap360Core
import SwiftUI

enum ActionKind: String, CaseIterable, Identifiable {
    case key, modTap, layerTap, layer, macro, device, mouse, transparent, none, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .key: "Key"
        case .modTap: "Mod-Tap"
        case .layerTap: "Layer-Tap"
        case .layer: "Layer"
        case .macro: "Macro"
        case .device: "Device"
        case .mouse: "Mouse"
        case .transparent: "Pass-thru"
        case .none: "Disabled"
        case .custom: "Code"
        }
    }

    var symbol: String {
        switch self {
        case .key: "keyboard"
        case .modTap: "hand.tap"
        case .layerTap: "square.stack.3d.down.right"
        case .layer: "square.3.layers.3d"
        case .macro: "text.append"
        case .device: "dot.radiowaves.left.and.right"
        case .mouse: "computermouse"
        case .transparent: "arrowtriangle.down"
        case .none: "nosign"
        case .custom: "chevron.left.forwardslash.chevron.right"
        }
    }

    var help: String {
        switch self {
        case .key: "Send a key, optionally with modifiers"
        case .modTap: "Tap for a key, hold for a modifier"
        case .layerTap: "Tap for a key, hold for a layer"
        case .layer: "Switch, hold or toggle a layer"
        case .macro: "Run a macro from your config"
        case .device: "Bluetooth, lighting, bootloader…"
        case .mouse: "Mouse buttons"
        case .transparent: "Use whatever the layer below has"
        case .none: "Do nothing"
        case .custom: "Write any ZMK binding by hand"
        }
    }

    init(_ b: KeyBinding, ctx: BindingContext) {
        switch b.behavior {
        case "kp": self = .key
        case "mt": self = .modTap
        case "lt": self = .layerTap
        case "mo", "tog", "to", "sl": self = .layer
        case "trans": self = .transparent
        case "none": self = .none
        case "mkp": self = .mouse
        case "bt", "out", "rgb_ug", "bl", "bootloader", "sys_reset", "studio_unlock", "stp", "caps_word", "key_repeat", "sk":
            self = .device
        default:
            if let c = ctx.customBehaviors[b.behavior] {
                if c.isMacro && c.bindingCells == 0 { self = .macro; return }
                if c.isHoldTap && c.bindingCells == 2 { self = .modTap; return }
            }
            self = .custom
        }
    }
}

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let binding = model.selectedBinding, let key = model.selectedKey {
                KeyEditor(binding: binding, keyIndex: key)
                    .id(key)
            } else {
                EmptyInspector()
            }
        }
        .frame(minWidth: 320, idealWidth: 350)
    }
}

private struct EmptyInspector: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Brand.gradient)
                    Text("Select a key to edit")
                        .font(.title3.weight(.semibold))
                    Text("Click any key on the keyboard to change what it does on this layer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

                VStack(alignment: .leading, spacing: 10) {
                    Text("TIPS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Tip(symbol: "arrow.up.and.down.and.arrow.left.and.right", text: "Arrow keys move between keys")
                    Tip(symbol: "hand.draw", text: "Drag a key onto another to swap them")
                    Tip(symbol: "doc.on.doc", text: "⌘C / ⌘V copy and paste a key")
                    Tip(symbol: "delete.left", text: "Delete makes a key pass-through")
                    Tip(symbol: "record.circle", text: "Use Record to press the key you want")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("LEGEND").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach([KeyLegend.Style.modifier, .holdTap, .layer, .system, .macro], id: \.self) { style in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill((Theme.tint(for: style, layer: 2) ?? .gray).opacity(0.25))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.tint(for: style, layer: 2) ?? .gray, lineWidth: 1))
                                .frame(width: 18, height: 14)
                            Text(Theme.styleName(style)).font(.callout)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(Theme.accent)
            Text(text).font(.callout)
        }
    }
}

// MARK: - Editor

private struct KeyEditor: View {
    @Environment(AppModel.self) private var model
    let binding: KeyBinding
    let keyIndex: Int

    var body: some View {
        let ctx = model.context
        let kind = ActionKind(binding, ctx: ctx)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(ctx: ctx)
                Divider()
                section("Action") { ActionGrid(selected: kind) { switchKind(to: $0) } }
                detail(kind: kind, ctx: ctx)
                section("Code") { CodeField(binding: binding) }
                quickActions
            }
            .padding(20)
        }
    }

    private func header(ctx: BindingContext) -> some View {
        HStack(alignment: .center, spacing: 14) {
            let phys = Adv360Layout.keys[keyIndex]
            KeyCapView(
                legend: binding.legend(in: ctx),
                ghost: binding == .trans ? model.selectedLayerIndex.flatMap { model.effectiveBinding(layer: $0, key: keyIndex) }?.legend(in: ctx) : nil,
                unit: 64
            )
            .frame(width: 64 * phys.w / 100, height: 64 * min(phys.h, 100) / 100)
            VStack(alignment: .leading, spacing: 4) {
                Text(binding.describe(in: ctx))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("Key \(keyIndex)")
                    Text("·")
                    Text(phys.isLeft ? "Left half" : "Right half")
                    if phys.isThumb { Text("·"); Text("Thumb") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detail(kind: ActionKind, ctx: BindingContext) -> some View {
        switch kind {
        case .key:
            section("Key") {
                KeyExprEditor(expr: KeyExpr(parsing: binding.param(0) ?? "A")) { model.setBinding(.kp($0.text)) }
            }
        case .modTap:
            ModTapEditor(binding: binding)
        case .layerTap:
            section("Hold for layer") {
                LayerList(selected: binding.layerRef ?? 1) { model.setBinding(KeyBinding("lt", [String($0), binding.param(1) ?? "SPACE"])) }
            }
            section("Tap for key") {
                KeyExprEditor(expr: KeyExpr(parsing: binding.param(1) ?? "SPACE")) {
                    model.setBinding(KeyBinding("lt", [binding.param(0) ?? "1", $0.text]))
                }
            }
        case .layer:
            LayerEditor(binding: binding)
        case .macro:
            section("Macro") { MacroList(binding: binding) }
        case .device:
            section("Function") { DeviceList(binding: binding) }
        case .mouse:
            section("Button") {
                OptionList(options: [
                    ("Left click", KeyBinding("mkp", ["LCLK"]), "computermouse"),
                    ("Right click", KeyBinding("mkp", ["RCLK"]), "computermouse"),
                    ("Middle click", KeyBinding("mkp", ["MCLK"]), "computermouse"),
                    ("Back", KeyBinding("mkp", ["MB4"]), "chevron.backward"),
                    ("Forward", KeyBinding("mkp", ["MB5"]), "chevron.forward"),
                ], current: binding, equivalents: ["MB1": "LCLK", "MB2": "RCLK", "MB3": "MCLK"])
            }
        case .transparent:
            InfoCard(symbol: "arrowtriangle.down.fill", text: "This key does whatever the nearest lower layer does. Most keys on extra layers should be pass-through so you only define what changes.")
        case .none:
            InfoCard(symbol: "nosign", text: "This key is disabled on this layer and blocks lower layers.")
        case .custom:
            InfoCard(symbol: "chevron.left.forwardslash.chevron.right", text: "This binding uses a behavior Remap360 doesn't have a visual editor for. Edit it below, it'll be written exactly as typed.")
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button { model.copySelection() } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { model.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            Spacer()
            Button(role: .destructive) { model.setBinding(.trans, name: "Clear Key") } label: { Label("Clear", systemImage: "eraser") }
                .disabled(binding == .trans)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    private func switchKind(to kind: ActionKind) {
        let current = ActionKind(binding, ctx: model.context)
        guard kind != current else { return }
        // Carry the key over when switching between key-based actions.
        let key: String = switch binding.behavior {
        case "kp": binding.param(0) ?? "A"
        case "mt", "lt": binding.param(1) ?? "A"
        default:
            if model.context.customBehaviors[binding.behavior]?.isHoldTap == true { binding.param(1) ?? "A" } else { "A" }
        }
        let firstOther = model.activeLayers.indices.first { $0 != model.selectedLayerIndex && $0 != 0 } ?? 1
        let new: KeyBinding = switch kind {
        case .key: .kp(key)
        case .modTap: KeyBinding("mt", ["LSHFT", key])
        case .layerTap: KeyBinding("lt", [String(firstOther), key])
        case .layer: KeyBinding("mo", [String(firstOther)])
        case .macro: model.macros.first.map { KeyBinding($0.label) } ?? .kp(key)
        case .device: KeyBinding("bt", ["BT_SEL", "0"])
        case .mouse: KeyBinding("mkp", ["LCLK"])
        case .transparent: .trans
        case .none: .none
        case .custom: binding
        }
        if kind == .custom { return }
        model.setBinding(new)
    }
}

// MARK: - Building blocks

@ViewBuilder
func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
        content()
    }
}

private struct ActionGrid: View {
    let selected: ActionKind
    let onSelect: (ActionKind) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(ActionKind.allCases) { kind in
                let isOn = kind == selected
                Button { onSelect(kind) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(height: 18)
                        Text(kind.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(isOn ? Brand.ink : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(kind.help)
            }
        }
    }
}

/// Key + modifier toggles + recorder + picker.
struct KeyExprEditor: View {
    let expr: KeyExpr
    let onChange: (KeyExpr) -> Void
    @State private var recorder = KeyRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach([ModifierFn.LC, .LA, .LS, .LG], id: \.self) { mod in
                    let on = expr.mods.contains(mod) || expr.mods.contains(rightVariant(mod))
                    Button {
                        var e = expr
                        if on { e.mods.removeAll { $0 == mod || $0 == rightVariant(mod) } } else { e.mods.append(mod) }
                        onChange(e)
                    } label: {
                        Text(mod.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 34, height: 28)
                            .background(on ? Theme.accent.opacity(0.9) : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .foregroundStyle(on ? Brand.ink : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Hold \(mod.name) with this key")
                }
                Spacer()
                Button {
                    if recorder.isRecording { recorder.stop() } else { recorder.start { onChange($0) } }
                } label: {
                    Label(recorder.isRecording ? "Press a key…" : "Record", systemImage: recorder.isRecording ? "record.circle.fill" : "record.circle")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(recorder.isRecording ? Color.red.opacity(0.15) : Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(recorder.isRecording ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help("Press a key combination on your keyboard to assign it")
            }
            KeyPicker(current: expr.text, onPick: { code in
                var e = expr
                e.key = code
                onChange(e)
            }, onPickShortcut: { onChange($0) })
        }
        .onDisappear { recorder.stop() }
    }

    private func rightVariant(_ m: ModifierFn) -> ModifierFn {
        switch m {
        case .LC: .RC
        case .LS: .RS
        case .LA: .RA
        case .LG: .RG
        default: m
        }
    }
}

private struct ModTapEditor: View {
    @Environment(AppModel.self) private var model
    let binding: KeyBinding

    var body: some View {
        let holdTaps = model.holdTaps
        let behavior = binding.behavior
        let mod = binding.param(0) ?? "LSHFT"
        let tap = binding.param(1) ?? "A"

        if !holdTaps.isEmpty {
            section("Style") {
                Picker("", selection: Binding(get: { behavior }, set: { model.setBinding(KeyBinding($0, [mod, tap])) })) {
                    Text("Standard (mt)").tag("mt")
                    ForEach(holdTaps) { ht in Text("\(ht.prettyName) (\(ht.label))").tag(ht.label) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        section("Hold for") {
            let mods = ["LCTRL", "LALT", "LSHFT", "LGUI", "RCTRL", "RALT", "RSHFT", "RGUI"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(mods, id: \.self) { m in
                    let def = Keycodes.lookup(m)!
                    let on = Keycodes.lookup(mod)?.code == m
                    Button { model.setBinding(KeyBinding(behavior, [m, tap])) } label: {
                        VStack(spacing: 1) {
                            Text(def.label).font(.system(size: 14, weight: .medium))
                            Text(m.hasPrefix("R") ? "right" : "left").font(.system(size: 8.5)).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Theme.accent.opacity(0.9) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(on ? Brand.ink : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(def.name)
                }
            }
        }
        section("Tap for") {
            KeyExprEditor(expr: KeyExpr(parsing: tap)) { model.setBinding(KeyBinding(behavior, [mod, $0.text])) }
        }
    }
}

private struct LayerEditor: View {
    @Environment(AppModel.self) private var model
    let binding: KeyBinding

    var body: some View {
        let modes: [(String, String, String)] = [
            ("mo", "Hold", "Active while the key is held"),
            ("tog", "Toggle", "Press once to turn on, again to turn off"),
            ("to", "Switch", "Switch to the layer and stay there"),
            ("sl", "One-shot", "Active for the next key press only"),
        ]
        let layer = binding.layerRef ?? 1
        section("Mode") {
            Picker("", selection: Binding(get: { binding.behavior }, set: { model.setBinding(KeyBinding($0, [String(layer)])) })) {
                ForEach(modes, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(modes.first { $0.0 == binding.behavior }?.2 ?? "")
                .font(.caption).foregroundStyle(.secondary)
        }
        section("Layer") {
            LayerList(selected: layer) { model.setBinding(KeyBinding(binding.behavior, [String($0)])) }
        }
    }
}

private struct LayerList: View {
    @Environment(AppModel.self) private var model
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.activeLayers.enumerated()), id: \.element.id) { i, layer in
                Button { onSelect(i) } label: {
                    HStack(spacing: 10) {
                        LayerBadge(index: i, size: 20)
                        Text(layer.displayName).font(.callout)
                        Spacer()
                        if i == selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(i == selected ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MacroList: View {
    @Environment(AppModel.self) private var model
    let binding: KeyBinding

    var body: some View {
        let macros = model.macros
        if macros.isEmpty {
            InfoCard(symbol: "text.append", text: "No macros found. Define them in config/macros.dtsi and they'll show up here.")
        } else {
            OptionList(options: macros.map { ($0.prettyName, KeyBinding($0.label), "text.append") }, current: binding)
            Text("Macros live in config/macros.dtsi.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DeviceList: View {
    let binding: KeyBinding

    var body: some View {
        let b = KeyBinding.init
        let groups: [(String, [(String, KeyBinding, String)])] = [
            ("Bluetooth", (0...4).map { ("Profile \($0)", b("bt", ["BT_SEL", "\($0)"]), "dot.radiowaves.left.and.right") } + [
                ("Next profile", b("bt", ["BT_NXT"]), "chevron.right"),
                ("Previous profile", b("bt", ["BT_PRV"]), "chevron.left"),
                ("Clear current profile", b("bt", ["BT_CLR"]), "xmark.circle"),
                ("Clear all profiles", b("bt", ["BT_CLR_ALL"]), "xmark.octagon"),
            ]),
            ("Output", [
                ("USB", b("out", ["OUT_USB"]), "cable.connector"),
                ("Bluetooth", b("out", ["OUT_BLE"]), "antenna.radiowaves.left.and.right"),
                ("Toggle USB / BT", b("out", ["OUT_TOG"]), "arrow.left.arrow.right"),
            ]),
            ("Lighting", [
                ("Backlight toggle", b("bl", ["BL_TOG"]), "lightbulb"),
                ("Backlight brighter", b("bl", ["BL_INC"]), "sun.max"),
                ("Backlight dimmer", b("bl", ["BL_DEC"]), "sun.min"),
                ("RGB toggle", b("rgb_ug", ["RGB_TOG"]), "rainbow"),
                ("RGB brighter", b("rgb_ug", ["RGB_BRI"]), "sun.max"),
                ("RGB dimmer", b("rgb_ug", ["RGB_BRD"]), "sun.min"),
                ("RGB next effect", b("rgb_ug", ["RGB_EFF"]), "sparkles"),
            ]),
            ("Typing", [
                ("Caps Word", b("caps_word", []), "textformat"),
                ("Key repeat", b("key_repeat", []), "repeat"),
                ("Sticky Shift", b("sk", ["LSHFT"]), "shift"),
                ("Sticky Command", b("sk", ["LGUI"]), "command"),
            ]),
            ("System", [
                ("Bootloader (flash mode)", b("bootloader", []), "arrow.down.circle"),
                ("Restart", b("sys_reset", []), "arrow.clockwise"),
                ("Unlock ZMK Studio", b("studio_unlock", []), "lock.open"),
                ("Show battery status", b("stp", ["STP_BAT"]), "battery.75percent"),
            ]),
        ]
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.0).font(.subheadline.weight(.semibold))
                    OptionList(options: group.1, current: binding)
                }
            }
        }
    }
}

private struct OptionList: View {
    @Environment(AppModel.self) private var model
    let options: [(String, KeyBinding, String)]
    let current: KeyBinding
    var equivalents: [String: String] = [:]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(options, id: \.1) { title, b, symbol in
                let on = normalize(current) == b
                Button { model.setBinding(b) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol).frame(width: 18).foregroundStyle(on ? Theme.accent : .secondary)
                        Text(title).font(.callout)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(on ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func normalize(_ b: KeyBinding) -> KeyBinding {
        var c = b
        c.params = c.params.map { equivalents[$0] ?? $0 }
        return c
    }
}

private struct CodeField: View {
    @Environment(AppModel.self) private var model
    let binding: KeyBinding
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("&kp A", text: $text)
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(apply)
            if text != binding.text {
                Button("Apply", action: apply).controlSize(.small).buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(invalid ? Color.red : (focused ? Theme.accent : .clear), lineWidth: 1.2))
        .onAppear { text = binding.text }
        .onChange(of: binding) { _, b in if !focused { text = b.text } }
        Text("The exact ZMK binding written to your keymap. Press Return to apply.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func apply() {
        let parsed = BindingParser.parse(text)
        guard parsed.count == 1 else { invalid = true; return }
        invalid = false
        model.setBinding(parsed[0])
        focused = false
    }
}

private struct InfoCard: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
