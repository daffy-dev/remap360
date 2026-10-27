import AppKit

/// Standard About panel with credits and the not-affiliated note.
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        let link: (String, String) -> NSAttributedString = { text, url in
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .link: URL(string: url)!])
        }
        credits.append(NSAttributedString(string: "A visual keymap editor for the Kinesis Advantage360 Pro.\n\n", attributes: body))
        credits.append(NSAttributedString(string: "Not affiliated with or endorsed by Kinesis Corporation. Advantage360 is a trademark of Kinesis Corporation.\n\n", attributes: body))
        credits.append(NSAttributedString(string: "Built on ", attributes: body))
        credits.append(link("ZMK Firmware", "https://zmk.dev"))
        credits.append(NSAttributedString(string: " and its Studio protocol, and Kinesis' MIT-licensed ", attributes: body))
        credits.append(link("Adv360-Pro-ZMK", "https://github.com/KinesisCorporation/Adv360-Pro-ZMK"))
        credits.append(NSAttributedString(string: " config.\n\n", attributes: body))
        credits.append(link("github.com/daffy-dev/remap360", "https://github.com/daffy-dev/remap360"))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 daffy-dev · MIT License",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
