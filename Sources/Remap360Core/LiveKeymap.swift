import Foundation

/// The keymap as it lives on a connected keyboard, plus translation to and from the
/// `KeyBinding` form the editor works with.
public struct LiveKeymap: Sendable {
    public var layers: [StudioLayer]
    public var behaviors: [Int32: StudioBehavior]
    public var availableLayers: UInt32
    public var maxLayerNameLength: UInt32

    /// Behavior id ↔ ZMK label (`kp`, `mo`, ... or a generated label for custom behaviors).
    public private(set) var labelByID: [Int32: String] = [:]
    public private(set) var idByLabel: [String: Int32] = [:]
    public private(set) var customBehaviors: [CustomBehavior] = []

    static let builtinLabels: [String: String] = [
        "key press": "kp", "mod-tap": "mt", "layer-tap": "lt", "momentary layer": "mo",
        "toggle layer": "tog", "to layer": "to", "sticky layer": "sl", "sticky key": "sk",
        "transparent": "trans", "none": "none", "bluetooth": "bt", "output selection": "out",
        "underglow": "rgb_ug", "rgb underglow": "rgb_ug", "backlight": "bl",
        "mouse key press": "mkp", "mouse button press": "mkp", "mouse button": "mkp",
        "reset": "sys_reset", "bootloader": "bootloader", "studio unlock": "studio_unlock",
        "caps word": "caps_word", "key repeat": "key_repeat", "battery level": "stp",
        "grave/escape": "gresc", "key toggle": "kt", "external power": "ext_power",
    ]

    public init(keymap: StudioKeymap, behaviors: [StudioBehavior]) {
        self.layers = keymap.layers
        self.availableLayers = keymap.availableLayers
        self.maxLayerNameLength = keymap.maxLayerNameLength
        self.behaviors = Dictionary(uniqueKeysWithValues: behaviors.map { ($0.id, $0) })

        var used = Set<String>()
        for b in behaviors.sorted(by: { $0.id < $1.id }) {
            let key = b.displayName.lowercased().trimmingCharacters(in: .whitespaces)
            var label: String
            if let builtin = Self.builtinLabels[key], !used.contains(builtin) {
                label = builtin
            } else {
                let base = b.displayName.map { $0.isLetter || $0.isNumber ? $0 : "_" }
                label = String(base).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                if label.isEmpty { label = "behavior_\(b.id)" }
                var candidate = label, n = 2
                while used.contains(candidate) || Self.builtinLabels.values.contains(candidate) { candidate = "\(label)_\(n)"; n += 1 }
                label = candidate
                let hidParams = b.metadata.first.map { set in
                    (set.param1.contains { if case .hidUsage = $0.kind { true } else { false } } ? 1 : 0)
                        + (set.param2.contains { if case .hidUsage = $0.kind { true } else { false } } ? 1 : 0)
                } ?? 0
                let cells = Self.paramCount(b)
                let compatible = (cells == 2 && hidParams == 2) ? "zmk,behavior-hold-tap"
                    : (cells == 0 ? "zmk,behavior-macro" : "zmk,behavior-studio")
                customBehaviors.append(CustomBehavior(label: label, compatible: compatible, bindingCells: cells, displayName: b.displayName))
            }
            used.insert(label)
            labelByID[b.id] = label
            idByLabel[label] = b.id
        }
    }

    static func paramCount(_ b: StudioBehavior) -> Int {
        func meaningful(_ values: [StudioParamValue]) -> Bool {
            values.contains { if case .nil_ = $0.kind { false } else { true } }
        }
        let p1 = b.metadata.contains { meaningful($0.param1) }
        let p2 = b.metadata.contains { meaningful($0.param2) }
        return p2 ? 2 : (p1 ? 1 : 0)
    }

    // MARK: Layers

    public func layerIndex(forID id: UInt32) -> Int? { layers.firstIndex { $0.id == id } }

    public func editorLayers() -> [Layer] {
        layers.map { l in
            var layer = Layer(nodeName: "layer_\(l.id)", displayName: l.name.isEmpty ? "Layer \(l.id)" : l.name,
                              bindings: l.bindings.map(keyBinding))
            layer.id = Self.stableID(l.id)
            return layer
        }
    }

    /// Deterministic UUID per layer id so selection survives refreshes.
    public static func stableID(_ layerID: UInt32) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", layerID))!
    }

    // MARK: Studio → editor

    static let btCommands = ["BT_CLR", "BT_NXT", "BT_PRV", "BT_SEL", "BT_CLR_ALL", "BT_DISC"]
    static let outCommands = ["OUT_TOG", "OUT_USB", "OUT_BLE"]
    static let rgbCommands = ["RGB_TOG", "RGB_ON", "RGB_OFF", "RGB_HUI", "RGB_HUD", "RGB_SAI", "RGB_SAD", "RGB_BRI",
                              "RGB_BRD", "RGB_SPI", "RGB_SPD", "RGB_EFF", "RGB_EFR", "RGB_EFS", "RGB_MEFS", "RGB_COLOR_HSB"]
    static let blCommands = ["BL_ON", "BL_OFF", "BL_TOG", "BL_INC", "BL_DEC", "BL_CYCLE", "BL_SET"]
    static let mouseButtons: [(String, UInt32)] = [("LCLK", 1), ("RCLK", 2), ("MCLK", 4), ("MB4", 8), ("MB5", 16)]

    public func keyBinding(_ b: StudioBinding) -> KeyBinding {
        guard let label = labelByID[b.behaviorID] else { return KeyBinding("behavior_\(b.behaviorID)", ["\(b.param1)", "\(b.param2)"]) }
        func layer(_ v: UInt32) -> String { layerIndex(forID: v).map(String.init) ?? "\(v)" }
        func cmd(_ list: [String], _ v: UInt32) -> String { Int(v) < list.count ? list[Int(v)] : "\(v)" }

        switch label {
        case "kp", "sk": return KeyBinding(label, [HIDUsage.decode(b.param1)])
        case "mt": return KeyBinding(label, [HIDUsage.decode(b.param1), HIDUsage.decode(b.param2)])
        case "lt": return KeyBinding(label, [layer(b.param1), HIDUsage.decode(b.param2)])
        case "mo", "tog", "to", "sl": return KeyBinding(label, [layer(b.param1)])
        case "bt":
            let c = cmd(Self.btCommands, b.param1)
            return KeyBinding(label, (c == "BT_SEL" || c == "BT_DISC") ? [c, "\(b.param2)"] : [c])
        case "out": return KeyBinding(label, [cmd(Self.outCommands, b.param1)])
        case "rgb_ug": return KeyBinding(label, [cmd(Self.rgbCommands, b.param1)])
        case "bl": return KeyBinding(label, [cmd(Self.blCommands, b.param1)])
        case "stp": return KeyBinding(label, ["STP_BAT"])
        case "mkp": return KeyBinding(label, [Self.mouseButtons.first { $0.1 == b.param1 }?.0 ?? "\(b.param1)"])
        default:
            let count = behaviors[b.behaviorID].map(Self.paramCount) ?? 0
            if let custom = customBehaviors.first(where: { $0.label == label }), custom.isHoldTap {
                return KeyBinding(label, [HIDUsage.decode(b.param1), HIDUsage.decode(b.param2)])
            }
            return KeyBinding(label, Array(["\(b.param1)", "\(b.param2)"].prefix(count)))
        }
    }

    // MARK: Editor → studio

    public enum ConversionError: LocalizedError {
        case unsupportedBehavior(String)
        case badParameter(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedBehavior(let b): "The keyboard's firmware doesn't include “\(b)”, so it can't be set live."
            case .badParameter(let p): "“\(p)” isn't something the keyboard understands."
            }
        }
    }

    public func studioBinding(_ k: KeyBinding) throws -> StudioBinding {
        guard let id = idByLabel[k.behavior] else { throw ConversionError.unsupportedBehavior(k.behavior) }
        func hid(_ i: Int) throws -> UInt32 {
            guard let p = k.param(i), let v = HIDUsage.encode(p) else { throw ConversionError.badParameter(k.param(i) ?? "?") }
            return v
        }
        func layer(_ i: Int) throws -> UInt32 {
            guard let p = k.param(i), let idx = Int(p), idx < layers.count else { throw ConversionError.badParameter(k.param(i) ?? "?") }
            return layers[idx].id
        }
        func cmd(_ list: [String], _ i: Int) throws -> UInt32 {
            guard let p = k.param(i) else { return 0 }
            if let n = list.firstIndex(of: p) { return UInt32(n) }
            if let n = UInt32(p) { return n }
            throw ConversionError.badParameter(p)
        }
        func num(_ i: Int) throws -> UInt32 {
            guard let p = k.param(i) else { return 0 }
            guard let n = UInt32(p) else { throw ConversionError.badParameter(p) }
            return n
        }

        switch k.behavior {
        case "kp", "sk": return StudioBinding(behaviorID: id, param1: try hid(0))
        case "mt": return StudioBinding(behaviorID: id, param1: try hid(0), param2: try hid(1))
        case "lt": return StudioBinding(behaviorID: id, param1: try layer(0), param2: try hid(1))
        case "mo", "tog", "to", "sl": return StudioBinding(behaviorID: id, param1: try layer(0))
        case "bt": return StudioBinding(behaviorID: id, param1: try cmd(Self.btCommands, 0), param2: try num(1))
        case "out": return StudioBinding(behaviorID: id, param1: try cmd(Self.outCommands, 0))
        case "rgb_ug": return StudioBinding(behaviorID: id, param1: try cmd(Self.rgbCommands, 0))
        case "bl": return StudioBinding(behaviorID: id, param1: try cmd(Self.blCommands, 0))
        case "stp": return StudioBinding(behaviorID: id)
        case "mkp":
            let p = k.param(0) ?? "LCLK"
            let alias = ["MB1": "LCLK", "MB2": "RCLK", "MB3": "MCLK"][p] ?? p
            guard let v = Self.mouseButtons.first(where: { $0.0 == alias })?.1 ?? UInt32(p) else { throw ConversionError.badParameter(p) }
            return StudioBinding(behaviorID: id, param1: v)
        default:
            if let custom = customBehaviors.first(where: { $0.label == k.behavior }), custom.isHoldTap {
                return StudioBinding(behaviorID: id, param1: try hid(0), param2: try hid(1))
            }
            return StudioBinding(behaviorID: id, param1: try num(0), param2: try num(1))
        }
    }

    public var supportsLabels: Set<String> { Set(idByLabel.keys) }
}
