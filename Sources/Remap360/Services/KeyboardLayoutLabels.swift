import Carbon
import Foundation
import Remap360Core

/// Asks macOS what each key position types in the currently selected keyboard layout
/// (Icelandic, German, ...), so keycaps show Æ instead of the US `;`.
enum KeyboardLayoutLabels {
    struct Result {
        var name: String
        var labels: [String: String]
        var shifted: [String: String]
        var option: [String: String]
    }

    static func current() -> Result? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "Keyboard layout"
        let layoutData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data

        func type(_ keyCode: UInt16, shift: Bool, option: Bool = false) -> String? {
            layoutData.withUnsafeBytes { raw -> String? in
                guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
                var deadKeys: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                var modifiers: UInt32 = 0
                if shift { modifiers |= UInt32(shiftKey >> 8) & 0xFF }
                if option { modifiers |= UInt32(optionKey >> 8) & 0xFF }
                let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), modifiers, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { return nil }
                let s = String(utf16CodeUnits: chars, count: length)
                // Only printable characters make sense as a legend.
                guard let scalar = s.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar),
                      !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return s
            }
        }

        var labels: [String: String] = [:]
        let printable: Set<KeyCategory> = [.letters, .numbers, .symbols]
        for def in Keycodes.all where printable.contains(def.category) {
            guard let mac = def.macKeyCode, let typed = type(mac, shift: false) else { continue }
            // Letters (including Æ, Ð, Ö, Þ on symbol positions) are shown uppercase like keycaps.
            let label = typed.allSatisfy(\.isLetter) ? typed.uppercased() : typed
            if label != def.label { labels[def.code] = label }
        }
        // Shifted symbols (`AT` = Shift+2) follow the layout too: on Icelandic Shift+2 types ".
        for (shiftedCode, baseCode) in HIDUsage.shiftedBases {
            guard let mac = Keycodes.lookup(baseCode)?.macKeyCode, let typed = type(mac, shift: true) else { continue }
            if typed != Keycodes.lookup(shiftedCode)?.label { labels[shiftedCode] = typed }
        }
        // Secondary characters for every printable key, skipping ones that just repeat the main legend.
        var shifted: [String: String] = [:], option: [String: String] = [:]
        for def in Keycodes.all where printable.contains(def.category) {
            guard let mac = def.macKeyCode else { continue }
            let main = labels[def.code] ?? def.label
            if let s = type(mac, shift: true), s.uppercased() != main.uppercased() { shifted[def.code] = s }
            if let o = type(mac, shift: false, option: true), o.uppercased() != main.uppercased() { option[def.code] = o }
        }
        return Result(name: name, labels: labels, shifted: shifted, option: option)
    }

    /// Posted by macOS when the user switches keyboard layout from the menu bar.
    static let changedNotification = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
}
