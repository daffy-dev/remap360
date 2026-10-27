import Foundation

public enum KeyCategory: String, CaseIterable, Sendable, Identifiable {
    case letters = "Letters"
    case numbers = "Numbers"
    case symbols = "Symbols"
    case shifted = "Shifted Symbols"
    case modifiers = "Modifiers"
    case editing = "Editing"
    case navigation = "Navigation"
    case function = "Function"
    case keypad = "Keypad"
    case media = "Media"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .letters: "textformat.abc"
        case .numbers: "textformat.123"
        case .symbols: "number"
        case .shifted: "exclamationmark"
        case .modifiers: "command"
        case .editing: "delete.left"
        case .navigation: "arrow.up.and.down.and.arrow.left.and.right"
        case .function: "fn"
        case .keypad: "square.grid.3x3"
        case .media: "playpause"
        }
    }
}

/// A HID key known to ZMK, with its canonical name, aliases and display legend.
public struct KeyDef: Sendable, Hashable, Identifiable {
    public let code: String
    public let aliases: [String]
    public let label: String
    public let name: String
    public let category: KeyCategory
    /// macOS virtual key code, used for "press a key to assign".
    public let macKeyCode: UInt16?

    public var id: String { code }
}

public enum Keycodes {
    private static func k(
        _ code: String, _ label: String, _ name: String, _ cat: KeyCategory,
        mac: UInt16? = nil, aliases: [String] = []
    ) -> KeyDef {
        KeyDef(code: code, aliases: aliases, label: label, name: name, category: cat, macKeyCode: mac)
    }

    public static let all: [KeyDef] = {
        var list: [KeyDef] = []
        let letterMac: [Character: UInt16] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11,
            "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35,
            "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
        ]
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            list.append(k(String(c), String(c), "Letter \(c)", .letters, mac: letterMac[c]))
        }
        let numMac: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        for n in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] {
            list.append(k("N\(n)", "\(n)", "Number \(n)", .numbers, mac: numMac[n], aliases: ["NUMBER_\(n)"]))
        }
        list += [
            k("MINUS", "-", "Minus", .symbols, mac: 27),
            k("EQUAL", "=", "Equal", .symbols, mac: 24, aliases: ["EQL"]),
            k("LBKT", "[", "Left Bracket", .symbols, mac: 33, aliases: ["LEFT_BRACKET"]),
            k("RBKT", "]", "Right Bracket", .symbols, mac: 30, aliases: ["RIGHT_BRACKET"]),
            k("BSLH", "\\", "Backslash", .symbols, mac: 42, aliases: ["BACKSLASH"]),
            k("SEMI", ";", "Semicolon", .symbols, mac: 41, aliases: ["SEMICOLON", "SCLN"]),
            k("SQT", "'", "Quote", .symbols, mac: 39, aliases: ["SINGLE_QUOTE", "APOSTROPHE", "APOS"]),
            k("GRAVE", "`", "Grave", .symbols, mac: 50),
            k("COMMA", ",", "Comma", .symbols, mac: 43),
            k("DOT", ".", "Period", .symbols, mac: 47, aliases: ["PERIOD"]),
            k("FSLH", "/", "Slash", .symbols, mac: 44, aliases: ["SLASH"]),
            k("NON_US_BSLH", "§", "ISO Backslash", .symbols, mac: 10, aliases: ["NUBS"]),

            k("EXCL", "!", "Exclamation", .shifted, aliases: ["EXCLAMATION"]),
            k("AT", "@", "At", .shifted, aliases: ["AT_SIGN"]),
            k("HASH", "#", "Hash", .shifted, aliases: ["POUND"]),
            k("DLLR", "$", "Dollar", .shifted, aliases: ["DOLLAR"]),
            k("PRCNT", "%", "Percent", .shifted, aliases: ["PERCENT"]),
            k("CARET", "^", "Caret", .shifted),
            k("AMPS", "&", "Ampersand", .shifted, aliases: ["AMPERSAND"]),
            k("STAR", "*", "Asterisk", .shifted, aliases: ["ASTERISK", "ASTRK"]),
            k("LPAR", "(", "Left Paren", .shifted, aliases: ["LEFT_PARENTHESIS"]),
            k("RPAR", ")", "Right Paren", .shifted, aliases: ["RIGHT_PARENTHESIS"]),
            k("UNDER", "_", "Underscore", .shifted, aliases: ["UNDERSCORE"]),
            k("PLUS", "+", "Plus", .shifted),
            k("LBRC", "{", "Left Brace", .shifted, aliases: ["LEFT_BRACE"]),
            k("RBRC", "}", "Right Brace", .shifted, aliases: ["RIGHT_BRACE"]),
            k("PIPE", "|", "Pipe", .shifted),
            k("COLON", ":", "Colon", .shifted),
            k("DQT", "\"", "Double Quote", .shifted, aliases: ["DOUBLE_QUOTES"]),
            k("TILDE", "~", "Tilde", .shifted),
            k("LT", "<", "Less Than", .shifted, aliases: ["LESS_THAN"]),
            k("GT", ">", "Greater Than", .shifted, aliases: ["GREATER_THAN"]),
            k("QMARK", "?", "Question", .shifted, aliases: ["QUESTION"]),

            k("LSHFT", "⇧", "Left Shift", .modifiers, mac: 56, aliases: ["LSHIFT", "LEFT_SHIFT"]),
            k("LCTRL", "⌃", "Left Control", .modifiers, mac: 59, aliases: ["LCTL", "LEFT_CONTROL"]),
            k("LALT", "⌥", "Left Option", .modifiers, mac: 58, aliases: ["LEFT_ALT", "LOPT"]),
            k("LGUI", "⌘", "Left Command", .modifiers, mac: 55, aliases: ["LCMD", "LWIN", "LMETA", "LEFT_GUI", "LEFT_WIN", "LEFT_COMMAND"]),
            k("RSHFT", "⇧", "Right Shift", .modifiers, mac: 60, aliases: ["RSHIFT", "RIGHT_SHIFT"]),
            k("RCTRL", "⌃", "Right Control", .modifiers, mac: 62, aliases: ["RCTL", "RIGHT_CONTROL"]),
            k("RALT", "⌥", "Right Option", .modifiers, mac: 61, aliases: ["RIGHT_ALT", "ROPT"]),
            k("RGUI", "⌘", "Right Command", .modifiers, mac: 54, aliases: ["RCMD", "RWIN", "RMETA", "RIGHT_GUI", "RIGHT_WIN", "RIGHT_COMMAND"]),
            k("CAPS", "⇪", "Caps Lock", .modifiers, mac: 57, aliases: ["CAPSLOCK", "CLCK"]),

            k("ESC", "Esc", "Escape", .editing, mac: 53, aliases: ["ESCAPE"]),
            k("TAB", "⇥", "Tab", .editing, mac: 48),
            k("RET", "⏎", "Return", .editing, mac: 36, aliases: ["ENTER", "RETURN"]),
            k("SPACE", "␣", "Space", .editing, mac: 49, aliases: ["SPC"]),
            k("BSPC", "⌫", "Backspace", .editing, mac: 51, aliases: ["BACKSPACE"]),
            k("DEL", "⌦", "Delete", .editing, mac: 117, aliases: ["DELETE"]),
            k("INS", "Ins", "Insert", .editing, mac: 114, aliases: ["INSERT"]),
            k("PSCRN", "PrtSc", "Print Screen", .editing, aliases: ["PRINTSCREEN"]),
            k("SLCK", "ScrLk", "Scroll Lock", .editing, aliases: ["SCROLLLOCK"]),
            k("PAUSE_BREAK", "Pause", "Pause", .editing, aliases: ["PAUSE"]),
            k("K_APP", "Menu", "Application", .editing, aliases: ["K_APPLICATION", "K_CONTEXT_MENU"]),

            k("LEFT", "←", "Left", .navigation, mac: 123, aliases: ["LEFT_ARROW"]),
            k("DOWN", "↓", "Down", .navigation, mac: 125, aliases: ["DOWN_ARROW"]),
            k("UP", "↑", "Up", .navigation, mac: 126, aliases: ["UP_ARROW"]),
            k("RIGHT", "→", "Right", .navigation, mac: 124, aliases: ["RIGHT_ARROW"]),
            k("HOME", "Home", "Home", .navigation, mac: 115),
            k("END", "End", "End", .navigation, mac: 119),
            k("PG_UP", "PgUp", "Page Up", .navigation, mac: 116, aliases: ["PAGE_UP"]),
            k("PG_DN", "PgDn", "Page Down", .navigation, mac: 121, aliases: ["PAGE_DOWN"]),
        ]
        let fMac: [Int: UInt16] = [
            1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97, 7: 98, 8: 100, 9: 101, 10: 109, 11: 103, 12: 111,
            13: 105, 14: 107, 15: 113, 16: 106, 17: 64, 18: 79, 19: 80, 20: 90,
        ]
        for n in 1...24 {
            list.append(k("F\(n)", "F\(n)", "F\(n)", .function, mac: fMac[n]))
        }
        let kpMac: [UInt16] = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
        for n in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] {
            list.append(k("KP_N\(n)", "\(n)", "Keypad \(n)", .keypad, mac: kpMac[n], aliases: ["KP_NUMBER_\(n)"]))
        }
        list += [
            k("KP_NUM", "Num", "Num Lock", .keypad, mac: 71, aliases: ["KP_NUMLOCK", "KP_NLCK"]),
            k("KP_DIVIDE", "/", "Keypad Divide", .keypad, mac: 75, aliases: ["KP_SLASH"]),
            k("KP_MULTIPLY", "*", "Keypad Multiply", .keypad, mac: 67, aliases: ["KP_ASTERISK"]),
            k("KP_MINUS", "−", "Keypad Minus", .keypad, mac: 78, aliases: ["KP_SUBTRACT"]),
            k("KP_PLUS", "+", "Keypad Plus", .keypad, mac: 69),
            k("KP_ENTER", "⌤", "Keypad Enter", .keypad, mac: 76),
            k("KP_DOT", ".", "Keypad Dot", .keypad, mac: 65),
            k("KP_EQUAL", "=", "Keypad Equal", .keypad, mac: 81),

            k("C_VOL_UP", "🔊", "Volume Up", .media, aliases: ["C_VOLUME_UP"]),
            k("C_VOL_DN", "🔉", "Volume Down", .media, aliases: ["C_VOLUME_DOWN"]),
            k("C_MUTE", "🔇", "Mute", .media),
            k("C_PP", "⏯", "Play / Pause", .media, aliases: ["C_PLAY_PAUSE"]),
            k("C_NEXT", "⏭", "Next Track", .media),
            k("C_PREV", "⏮", "Previous Track", .media, aliases: ["C_PREVIOUS"]),
            k("C_STOP", "⏹", "Stop", .media),
            k("C_BRI_UP", "☀︎+", "Brightness Up", .media, aliases: ["C_BRIGHTNESS_INC"]),
            k("C_BRI_DN", "☀︎−", "Brightness Down", .media, aliases: ["C_BRIGHTNESS_DEC"]),
            k("C_EJECT", "⏏", "Eject", .media),
            k("C_AL_CALC", "Calc", "Calculator", .media, aliases: ["C_AL_CALCULATOR"]),
        ]
        return list
    }()

    private static let byName: [String: KeyDef] = {
        var map: [String: KeyDef] = [:]
        for def in all {
            map[def.code] = def
            for a in def.aliases { map[a] = def }
        }
        return map
    }()

    private static let byMac: [UInt16: KeyDef] = {
        var map: [UInt16: KeyDef] = [:]
        for def in all { if let m = def.macKeyCode, map[m] == nil { map[m] = def } }
        return map
    }()

    public static func lookup(_ name: String) -> KeyDef? { byName[name] }
    public static func lookup(macKeyCode: UInt16) -> KeyDef? { byMac[macKeyCode] }

    public static func search(_ query: String) -> [KeyDef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { def in
            def.label.lowercased() == q
                || def.code.lowercased().contains(q)
                || def.name.lowercased().contains(q)
                || def.aliases.contains { $0.lowercased().contains(q) }
        }
    }
}

/// Modifier wrappers usable around a keycode, e.g. `LG(LS(S))`.
public enum ModifierFn: String, CaseIterable, Sendable, Hashable {
    case LC, LS, LA, LG, RC, RS, RA, RG

    public var symbol: String {
        switch self {
        case .LC, .RC: "⌃"
        case .LS, .RS: "⇧"
        case .LA, .RA: "⌥"
        case .LG, .RG: "⌘"
        }
    }

    public var name: String {
        switch self {
        case .LC: "Control"
        case .LS: "Shift"
        case .LA: "Option"
        case .LG: "Command"
        case .RC: "Right Control"
        case .RS: "Right Shift"
        case .RA: "Right Option"
        case .RG: "Right Command"
        }
    }

    /// Order used by macOS when displaying shortcuts: ⌃⌥⇧⌘.
    var displayOrder: Int {
        switch self {
        case .LC, .RC: 0
        case .LA, .RA: 1
        case .LS, .RS: 2
        case .LG, .RG: 3
        }
    }

    /// The bare modifier keycode with the same meaning.
    public var keyCode: String {
        switch self {
        case .LC: "LCTRL"
        case .LS: "LSHFT"
        case .LA: "LALT"
        case .LG: "LGUI"
        case .RC: "RCTRL"
        case .RS: "RSHFT"
        case .RA: "RALT"
        case .RG: "RGUI"
        }
    }
}

/// A keycode expression: base key plus zero or more modifier wrappers.
public struct KeyExpr: Sendable, Hashable {
    public var key: String
    public var mods: [ModifierFn]

    public init(key: String, mods: [ModifierFn] = []) {
        self.key = key
        self.mods = mods
    }

    /// Parses `LS(LG(S))`, `LG(SPACE)`, `A`. Unparseable input becomes a plain key string.
    public init(parsing text: String) {
        var s = text.replacingOccurrences(of: " ", with: "")
        var mods: [ModifierFn] = []
        while let open = s.firstIndex(of: "("), s.hasSuffix(")"),
              let m = ModifierFn(rawValue: String(s[..<open])) {
            mods.append(m)
            s = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
        }
        self.key = s
        self.mods = mods
    }

    public var text: String {
        mods.reversed().reduce(key) { inner, m in "\(m.rawValue)(\(inner))" }
    }

    public var def: KeyDef? { Keycodes.lookup(key) }

    public var label: String { label(using: [:]) }

    /// Legend text; `overrides` maps canonical key codes to what the Mac's keyboard layout types.
    public func label(using overrides: [String: String]) -> String {
        let code = def?.code ?? key
        let base = overrides[code] ?? def?.label ?? key
        let modText = mods.sorted { $0.displayOrder < $1.displayOrder }.map(\.symbol).joined()
        return modText + base
    }
}

/// Ready-made macOS shortcuts. They're ordinary key presses with modifiers, so they work
/// everywhere (live and in the config file); the editor just gives them friendly names.
public struct MacShortcut: Sendable, Hashable, Identifiable {
    public let expr: String
    public let name: String
    public let short: String
    public let symbol: String

    public var id: String { expr }

    public static let all: [MacShortcut] = [
        MacShortcut(expr: "LC(UP)", name: "Mission Control", short: "Mission", symbol: "rectangle.3.group"),
        MacShortcut(expr: "LC(DOWN)", name: "App Windows", short: "App Wins", symbol: "macwindow.on.rectangle"),
        MacShortcut(expr: "LC(LEFT)", name: "Previous Space", short: "Space ←", symbol: "rectangle.lefthalf.inset.filled.arrow.left"),
        MacShortcut(expr: "LC(RIGHT)", name: "Next Space", short: "Space →", symbol: "rectangle.righthalf.inset.filled.arrow.right"),
        MacShortcut(expr: "LG(SPACE)", name: "Spotlight", short: "Spotlight", symbol: "magnifyingglass"),
        MacShortcut(expr: "LS(LG(N5))", name: "Screenshot & Recording", short: "Capture", symbol: "camera.viewfinder"),
        MacShortcut(expr: "LS(LG(N4))", name: "Screenshot Area", short: "Snip", symbol: "crop"),
        MacShortcut(expr: "LC(LG(Q))", name: "Lock Screen", short: "Lock", symbol: "lock"),
        MacShortcut(expr: "LC(LG(SPACE))", name: "Emoji & Symbols", short: "Emoji", symbol: "face.smiling"),
        MacShortcut(expr: "LA(LG(ESC))", name: "Force Quit", short: "Force Quit", symbol: "xmark.octagon"),
        MacShortcut(expr: "LC(SPACE)", name: "Switch Input Language", short: "Language", symbol: "globe"),
        MacShortcut(expr: "LG(TAB)", name: "Last App", short: "Last App", symbol: "square.on.square"),
    ]

    /// Compares by the value the keyboard actually sends, so `LG(PRCNT)` matches `LS(LG(N5))`.
    public static func match(_ text: String) -> MacShortcut? {
        guard let value = HIDUsage.encode(text) else { return nil }
        return all.first { HIDUsage.encode($0.expr) == value }
    }
}
