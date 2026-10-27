import Foundation

/// A single ZMK binding such as `&kp A`, `&mt LSHFT A` or `&mo 3`.
public struct KeyBinding: Sendable, Hashable {
    public var behavior: String
    public var params: [String]

    public init(_ behavior: String, _ params: [String] = []) {
        self.behavior = behavior
        self.params = params
    }

    public static let trans = KeyBinding("trans")
    public static let none = KeyBinding("none")
    public static func kp(_ key: String) -> KeyBinding { KeyBinding("kp", [key]) }

    public var text: String {
        (["&" + behavior] + params).joined(separator: " ")
    }

    public func param(_ i: Int) -> String? { i < params.count ? params[i] : nil }

    /// Layer index referenced by this binding, if any.
    public var layerRef: Int? {
        switch behavior {
        case "mo", "tog", "to", "sl", "lt": param(0).flatMap(Int.init)
        default: nil
        }
    }

    public func withLayerRef(_ layer: Int) -> KeyBinding {
        guard layerRef != nil else { return self }
        var copy = self
        copy.params[0] = String(layer)
        return copy
    }
}

public enum BindingParser {
    /// Splits the contents of `bindings = < ... >` into bindings.
    /// Parentheses are respected so `LS( A )` stays one parameter.
    public static func parse(_ text: String) -> [KeyBinding] {
        let clean = stripComments(text)
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for ch in clean {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth = max(0, depth - 1) }
            if ch.isWhitespace && depth == 0 {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var result: [KeyBinding] = []
        for token in tokens {
            if token.hasPrefix("&") {
                result.append(KeyBinding(String(token.dropFirst())))
            } else if !result.isEmpty {
                result[result.count - 1].params.append(token.replacingOccurrences(of: " ", with: ""))
            }
        }
        return result
    }

    public static func stripComments(_ text: String) -> String {
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let rest = text[i...]
            if rest.hasPrefix("//") {
                i = text[i...].firstIndex(of: "\n") ?? text.endIndex
            } else if rest.hasPrefix("/*") {
                if let end = text.range(of: "*/", range: i..<text.endIndex) {
                    i = end.upperBound
                } else {
                    i = text.endIndex
                }
                out.append(" ")
            } else {
                out.append(text[i])
                i = text.index(after: i)
            }
        }
        return out
    }
}

/// A behavior defined in the user's config (macro, hold-tap, ...), discovered while parsing.
public struct CustomBehavior: Sendable, Hashable, Identifiable {
    public let label: String
    public let compatible: String
    public let bindingCells: Int
    public let displayName: String?

    public var id: String { label }
    public var isMacro: Bool { compatible == "zmk,behavior-macro" }
    public var isHoldTap: Bool { compatible == "zmk,behavior-hold-tap" }

    public init(label: String, compatible: String, bindingCells: Int, displayName: String?) {
        self.label = label
        self.compatible = compatible
        self.bindingCells = bindingCells
        self.displayName = displayName
    }

    public var prettyName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if label == "macro_ver" { return "Version" }
        return label
            .replacingOccurrences(of: "macro_", with: "")
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// How a binding should be drawn on a keycap.
public struct KeyLegend: Sendable, Hashable {
    public enum Style: Sendable, Hashable {
        case key, modifier, layer, transparent, none, system, macro, holdTap, unknown
    }

    public var tap: String
    public var hold: String?
    public var style: Style
    public var layer: Int?
    public var symbol: String?
    /// What the key types with Shift / Option held, shown small in the corners like a real keycap.
    public var shifted: String?
    public var option: String?

    public init(tap: String, hold: String? = nil, style: Style, layer: Int? = nil, symbol: String? = nil) {
        self.tap = tap
        self.hold = hold
        self.style = style
        self.layer = layer
        self.symbol = symbol
    }
}

public struct BindingContext: Sendable {
    public var layerNames: [String]
    public var customBehaviors: [String: CustomBehavior]
    /// Canonical key code → character it types in the user's Mac keyboard layout (e.g. SEMI → "Æ").
    public var keyLabels: [String: String]
    public var shiftLabels: [String: String]
    public var optionLabels: [String: String]

    public init(layerNames: [String] = [], customBehaviors: [String: CustomBehavior] = [:], keyLabels: [String: String] = [:],
                shiftLabels: [String: String] = [:], optionLabels: [String: String] = [:]) {
        self.layerNames = layerNames
        self.customBehaviors = customBehaviors
        self.keyLabels = keyLabels
        self.shiftLabels = shiftLabels
        self.optionLabels = optionLabels
    }

    public func layerName(_ i: Int?) -> String {
        guard let i else { return "?" }
        return i < layerNames.count ? layerNames[i] : "Layer \(i)"
    }
}

extension KeyBinding {
    public func legend(in ctx: BindingContext) -> KeyLegend {
        let p0 = param(0), p1 = param(1)
        func keyLabel(_ s: String?) -> String { s.map { KeyExpr(parsing: $0).label(using: ctx.keyLabels) } ?? "?" }
        func isMod(_ s: String?) -> Bool { s.flatMap { KeyExpr(parsing: $0).def?.category == .modifiers } ?? false }

        switch behavior {
        case "kp" where p0.flatMap(MacShortcut.match) != nil:
            let s = MacShortcut.match(p0!)!
            return KeyLegend(tap: s.short, style: .system, symbol: s.symbol)
        case "kp":
            var legend = KeyLegend(tap: keyLabel(p0), style: isMod(p0) ? .modifier : .key)
            let expr = KeyExpr(parsing: p0 ?? "")
            if expr.mods.isEmpty, let code = expr.def?.code {
                legend.shifted = ctx.shiftLabels[code]
                legend.option = ctx.optionLabels[code]
            }
            return legend
        case "mt":
            return KeyLegend(tap: keyLabel(p1), hold: keyLabel(p0), style: .holdTap)
        case "lt":
            let l = layerRef
            return KeyLegend(tap: keyLabel(p1), hold: ctx.layerName(l), style: .layer, layer: l)
        case "mo":
            return KeyLegend(tap: ctx.layerName(layerRef), hold: "hold", style: .layer, layer: layerRef, symbol: "hand.point.down")
        case "tog":
            return KeyLegend(tap: ctx.layerName(layerRef), hold: "toggle", style: .layer, layer: layerRef, symbol: "switch.2")
        case "to":
            return KeyLegend(tap: ctx.layerName(layerRef), hold: "go to", style: .layer, layer: layerRef, symbol: "arrow.right.to.line")
        case "sl":
            return KeyLegend(tap: ctx.layerName(layerRef), hold: "one-shot", style: .layer, layer: layerRef, symbol: "1.circle")
        case "sk":
            return KeyLegend(tap: keyLabel(p0), hold: "sticky", style: .modifier)
        case "trans":
            return KeyLegend(tap: "", style: .transparent, symbol: "arrowtriangle.down")
        case "none":
            return KeyLegend(tap: "", style: .none)
        case "bt":
            switch p0 {
            case "BT_SEL": return KeyLegend(tap: "BT \(p1 ?? "")", hold: "select", style: .system, symbol: "dot.radiowaves.left.and.right")
            case "BT_CLR": return KeyLegend(tap: "BT", hold: "clear", style: .system, symbol: "dot.radiowaves.left.and.right")
            case "BT_CLR_ALL": return KeyLegend(tap: "BT", hold: "clear all", style: .system, symbol: "dot.radiowaves.left.and.right")
            case "BT_NXT": return KeyLegend(tap: "BT", hold: "next", style: .system, symbol: "dot.radiowaves.left.and.right")
            case "BT_PRV": return KeyLegend(tap: "BT", hold: "prev", style: .system, symbol: "dot.radiowaves.left.and.right")
            case "BT_DISC": return KeyLegend(tap: "BT \(p1 ?? "")", hold: "disconnect", style: .system, symbol: "dot.radiowaves.left.and.right")
            default: return KeyLegend(tap: "BT", hold: p0, style: .system, symbol: "dot.radiowaves.left.and.right")
            }
        case "out":
            let map = ["OUT_USB": "USB", "OUT_BLE": "BLE", "OUT_TOG": "Toggle"]
            return KeyLegend(tap: map[p0 ?? ""] ?? (p0 ?? ""), hold: "output", style: .system, symbol: "cable.connector")
        case "rgb_ug":
            let map = ["RGB_TOG": "toggle", "RGB_ON": "on", "RGB_OFF": "off", "RGB_BRI": "bright +", "RGB_BRD": "bright −",
                       "RGB_HUI": "hue +", "RGB_HUD": "hue −", "RGB_SAI": "sat +", "RGB_SAD": "sat −",
                       "RGB_EFF": "effect +", "RGB_EFR": "effect −", "RGB_SPI": "speed +", "RGB_SPD": "speed −"]
            return KeyLegend(tap: "RGB", hold: map[p0 ?? ""] ?? p0, style: .system, symbol: "rainbow")
        case "bl":
            let map = ["BL_TOG": "toggle", "BL_ON": "on", "BL_OFF": "off", "BL_INC": "bright +", "BL_DEC": "bright −", "BL_CYCLE": "cycle"]
            return KeyLegend(tap: "Light", hold: map[p0 ?? ""] ?? p0, style: .system, symbol: "lightbulb")
        case "mkp":
            let map = ["MB1": "Left", "LCLK": "Left", "MB2": "Right", "RCLK": "Right", "MB3": "Middle", "MCLK": "Middle", "MB4": "Back", "MB5": "Forward"]
            return KeyLegend(tap: map[p0 ?? ""] ?? (p0 ?? ""), hold: "click", style: .system, symbol: "computermouse")
        case "stp":
            return KeyLegend(tap: "Battery", hold: "status", style: .system, symbol: "battery.75percent")
        case "bootloader":
            return KeyLegend(tap: "Boot", hold: "loader", style: .system, symbol: "arrow.down.circle")
        case "sys_reset":
            return KeyLegend(tap: "Reset", style: .system, symbol: "arrow.clockwise")
        case "studio_unlock":
            return KeyLegend(tap: "Studio", hold: "unlock", style: .system, symbol: "lock.open")
        case "caps_word":
            return KeyLegend(tap: "Caps", hold: "word", style: .modifier, symbol: "textformat")
        case "key_repeat":
            return KeyLegend(tap: "Repeat", style: .system, symbol: "repeat")
        default:
            if let custom = ctx.customBehaviors[behavior] {
                if custom.isHoldTap, params.count == 2 {
                    return KeyLegend(tap: keyLabel(p1), hold: keyLabel(p0), style: .holdTap)
                }
                return KeyLegend(tap: custom.prettyName, style: .macro, symbol: custom.isMacro ? "text.append" : nil)
            }
            return KeyLegend(tap: behavior, hold: params.isEmpty ? nil : params.joined(separator: " "), style: .unknown)
        }
    }

    /// Plain-English description used in the inspector and tooltips.
    public func describe(in ctx: BindingContext) -> String {
        func keyName(_ s: String?) -> String {
            guard let s else { return "?" }
            let e = KeyExpr(parsing: s)
            let mods = e.mods.map(\.name)
            let code = e.def?.code ?? e.key
            let base = ctx.keyLabels[code].map { "“\($0)”" } ?? e.def?.name ?? e.key
            return (mods + [base]).joined(separator: " + ")
        }
        switch behavior {
        case "kp":
            if let s = param(0).flatMap(MacShortcut.match) { return "\(s.name) (\(KeyExpr(parsing: s.expr).label))" }
            return "Sends \(keyName(param(0)))"
        case "mt": return "Tap for \(keyName(param(1))), hold for \(keyName(param(0)))"
        case "lt": return "Tap for \(keyName(param(1))), hold for layer “\(ctx.layerName(layerRef))”"
        case "mo": return "Activates “\(ctx.layerName(layerRef))” while held"
        case "tog": return "Toggles “\(ctx.layerName(layerRef))” on and off"
        case "to": return "Switches to “\(ctx.layerName(layerRef))”"
        case "sl": return "Activates “\(ctx.layerName(layerRef))” for the next key press"
        case "sk": return "Sticky \(keyName(param(0))) for the next key press"
        case "trans": return "Pass-through: uses the key from the layer below"
        case "none": return "Does nothing"
        case "bootloader": return "Reboots this half into bootloader (flash) mode"
        case "sys_reset": return "Restarts this half"
        case "studio_unlock": return "Unlocks ZMK Studio for live editing"
        case "caps_word": return "Caps Word: capitalizes until a non-word key"
        case "key_repeat": return "Repeats the last key"
        default:
            if let c = ctx.customBehaviors[behavior] {
                if c.isMacro { return "Runs macro “\(c.prettyName)”" }
                if c.isHoldTap, params.count == 2 {
                    return "Tap for \(keyName(param(1))), hold for \(keyName(param(0))) (\(c.label))"
                }
            }
            return text
        }
    }
}
