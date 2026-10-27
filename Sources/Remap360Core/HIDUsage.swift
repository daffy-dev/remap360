import Foundation

/// Converts between ZMK key names and the 32-bit values the firmware uses:
/// `mods << 24 | page << 16 | usage id` (see dt-bindings/zmk/modifiers.h and hid_usage_pages.h).
public enum HIDUsage {
    static let keyboardPage: UInt32 = 0x07
    static let consumerPage: UInt32 = 0x0C

    /// Canonical code → (page, id). Shifted symbols are expressed via `shifted`.
    static let table: [String: (UInt32, UInt32)] = {
        var t: [String: (UInt32, UInt32)] = [:]
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for (i, c) in letters.enumerated() { t[String(c)] = (0x07, 0x04 + UInt32(i)) }
        for n in 1...9 { t["N\(n)"] = (0x07, 0x1E + UInt32(n - 1)) }
        t["N0"] = (0x07, 0x27)
        let k: [(String, UInt32)] = [
            ("RET", 0x28), ("ESC", 0x29), ("BSPC", 0x2A), ("TAB", 0x2B), ("SPACE", 0x2C), ("MINUS", 0x2D),
            ("EQUAL", 0x2E), ("LBKT", 0x2F), ("RBKT", 0x30), ("BSLH", 0x31), ("SEMI", 0x33), ("SQT", 0x34),
            ("GRAVE", 0x35), ("COMMA", 0x36), ("DOT", 0x37), ("FSLH", 0x38), ("CAPS", 0x39),
            ("PSCRN", 0x46), ("SLCK", 0x47), ("PAUSE_BREAK", 0x48), ("INS", 0x49), ("HOME", 0x4A), ("PG_UP", 0x4B),
            ("DEL", 0x4C), ("END", 0x4D), ("PG_DN", 0x4E), ("RIGHT", 0x4F), ("LEFT", 0x50), ("DOWN", 0x51), ("UP", 0x52),
            ("KP_NUM", 0x53), ("KP_DIVIDE", 0x54), ("KP_MULTIPLY", 0x55), ("KP_MINUS", 0x56), ("KP_PLUS", 0x57),
            ("KP_ENTER", 0x58), ("KP_DOT", 0x63), ("NON_US_BSLH", 0x64), ("K_APP", 0x65), ("KP_EQUAL", 0x67),
            ("LCTRL", 0xE0), ("LSHFT", 0xE1), ("LALT", 0xE2), ("LGUI", 0xE3),
            ("RCTRL", 0xE4), ("RSHFT", 0xE5), ("RALT", 0xE6), ("RGUI", 0xE7),
        ]
        for (name, id) in k { t[name] = (0x07, id) }
        for n in 1...9 { t["KP_N\(n)"] = (0x07, 0x59 + UInt32(n - 1)) }
        t["KP_N0"] = (0x07, 0x62)
        for n in 1...12 { t["F\(n)"] = (0x07, 0x3A + UInt32(n - 1)) }
        for n in 13...24 { t["F\(n)"] = (0x07, 0x68 + UInt32(n - 13)) }
        let consumer: [(String, UInt32)] = [
            ("C_VOL_UP", 0xE9), ("C_VOL_DN", 0xEA), ("C_MUTE", 0xE2), ("C_PP", 0xCD), ("C_NEXT", 0xB5),
            ("C_PREV", 0xB6), ("C_STOP", 0xB7), ("C_BRI_UP", 0x6F), ("C_BRI_DN", 0x70), ("C_EJECT", 0xB8),
            ("C_AL_CALC", 0x192),
        ]
        for (name, id) in consumer { t[name] = (0x0C, id) }
        return t
    }()

    /// Shifted symbol names and the base key they shift.
    static let shifted: [String: String] = [
        "EXCL": "N1", "AT": "N2", "HASH": "N3", "DLLR": "N4", "PRCNT": "N5", "CARET": "N6", "AMPS": "N7",
        "STAR": "N8", "LPAR": "N9", "RPAR": "N0", "UNDER": "MINUS", "PLUS": "EQUAL", "LBRC": "LBKT",
        "RBRC": "RBKT", "PIPE": "BSLH", "COLON": "SEMI", "DQT": "SQT", "TILDE": "GRAVE", "LT": "COMMA",
        "GT": "DOT", "QMARK": "FSLH",
    ]

    public static var shiftedBases: [String: String] { shifted }

    static let modBits: [(ModifierFn, UInt32)] = [
        (.LC, 0x01), (.LS, 0x02), (.LA, 0x04), (.LG, 0x08), (.RC, 0x10), (.RS, 0x20), (.RA, 0x40), (.RG, 0x80),
    ]

    private static let reverse: [UInt32: String] = {
        var r: [UInt32: String] = [:]
        for (name, (page, id)) in table { r[page << 16 | id] = name }
        return r
    }()

    private static let reverseShifted: [String: String] = {
        Dictionary(uniqueKeysWithValues: shifted.map { ($1, $0) })
    }()

    /// `LG(LS(A))` → 0x0A070004. Returns nil for unknown keys.
    public static func encode(_ text: String) -> UInt32? {
        let expr = KeyExpr(parsing: text)
        var key = Keycodes.lookup(expr.key)?.code ?? expr.key
        var mods: UInt32 = 0
        if let base = shifted[key] {
            key = base
            mods |= 0x02
        }
        guard let (page, id) = table[key] else { return nil }
        for m in expr.mods { mods |= modBits.first { $0.0 == m }!.1 }
        return mods << 24 | page << 16 | id
    }

    /// 0x0A070004 → `LG(LS(A))`, preferring named shifted symbols (`LS(N1)` → `EXCL`).
    public static func decode(_ value: UInt32) -> String {
        var mods = value >> 24
        let usage = value & 0x00FF_FFFF
        let page = (usage >> 16) & 0xFF
        // ZMK accepts a bare id with page 0 as keyboard page.
        let normalized = page == 0 ? (keyboardPage << 16 | usage) : usage
        guard var name = reverse[normalized] else { return String(format: "0x%08X", value) }
        if mods & 0x02 != 0, let sym = reverseShifted[name] {
            name = sym
            mods &= ~0x02
        }
        let wrappers = modBits.filter { mods & $0.1 != 0 }.map(\.0)
        return KeyExpr(key: name, mods: wrappers).text
    }
}
