import Foundation

public struct Layer: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var nodeName: String
    public var nodeLabel: String?
    public var displayName: String
    public var bindings: [KeyBinding]
    public var status: String?
    /// Properties we don't edit (e.g. `sensor-bindings`), kept verbatim without the trailing `;`.
    public var extraProps: [String]

    public init(nodeName: String, nodeLabel: String? = nil, displayName: String, bindings: [KeyBinding],
                status: String? = nil, extraProps: [String] = []) {
        self.nodeName = nodeName
        self.nodeLabel = nodeLabel
        self.displayName = displayName
        self.bindings = bindings
        self.status = status
        self.extraProps = extraProps
    }

    public var isReserved: Bool { status == "reserved" }
}

public enum KeymapError: LocalizedError {
    case keymapNodeNotFound
    case unbalanced

    public var errorDescription: String? {
        switch self {
        case .keymapNodeNotFound: "Couldn't find a `zmk,keymap` node in the keymap file."
        case .unbalanced: "The keymap file has unbalanced braces."
        }
    }
}

/// A parsed `adv360.keymap`. Only the `keymap { ... }` node is regenerated on save;
/// everything else in the file is preserved byte for byte.
public struct KeymapDocument: Sendable {
    public var original: String
    public var layers: [Layer]
    public var customBehaviors: [CustomBehavior]
    /// Non-layer properties in the keymap node besides `compatible`.
    var keymapProps: [String]
    var keymapBodyRange: Range<String.Index>
    var baseIndent: String

    public var activeLayers: [Layer] { layers.filter { !$0.isReserved } }

    public init(text: String, extraSources: [String] = []) throws {
        original = text
        let scanner = DTScanner(text)
        let nodes = scanner.nodes()
        guard let keymap = nodes.first(where: { node in
            node.depth >= 1 && text[node.body].contains("\"zmk,keymap\"")
                && (node.name == "keymap" || node.label == "keymap")
        }) ?? nodes.first(where: { text[$0.body].contains("\"zmk,keymap\"") && $0.name != "/" })
        else { throw KeymapError.keymapNodeNotFound }

        keymapBodyRange = keymap.body
        baseIndent = Self.indent(of: keymap.start, in: text)

        var layers: [Layer] = []
        var keymapProps: [String] = []
        let bodyText = String(text[keymap.body])
        let inner = DTScanner(bodyText)
        for item in inner.topLevelItems() {
            switch item {
            case .property(let raw):
                if !raw.hasPrefix("compatible") { keymapProps.append(raw) }
            case .node(let label, let name, let body):
                var layer = Layer(nodeName: name, nodeLabel: label, displayName: name, bindings: [])
                for case .property(let raw) in DTScanner(body).topLevelItems() {
                    let (key, value) = Self.splitProp(raw)
                    switch key {
                    case "display-name":
                        layer.displayName = Self.unquote(value)
                    case "bindings":
                        layer.bindings = BindingParser.parse(Self.stripAngles(value))
                    case "status":
                        layer.status = Self.unquote(value)
                    default:
                        layer.extraProps.append(raw)
                    }
                }
                layers.append(layer)
            }
        }
        self.layers = layers
        self.keymapProps = keymapProps

        var behaviors: [CustomBehavior] = []
        for source in [text] + extraSources {
            let s = DTScanner(source)
            for node in s.nodes() {
                let body = DTScanner(String(source[node.body])).topLevelItems()
                var compatible: String?, cells = 0, display: String?
                for case .property(let raw) in body {
                    let (key, value) = Self.splitProp(raw)
                    if key == "compatible" { compatible = Self.unquote(value) }
                    if key == "#binding-cells" { cells = Int(Self.stripAngles(value).trimmingCharacters(in: .whitespaces)) ?? 0 }
                    if key == "display-name" { display = Self.unquote(value) }
                }
                if let compatible, compatible.hasPrefix("zmk,behavior"), let label = node.label {
                    behaviors.append(CustomBehavior(label: label, compatible: compatible, bindingCells: cells, displayName: display))
                }
            }
        }
        self.customBehaviors = behaviors
    }

    // MARK: Writing

    public func render() -> String {
        var out = original
        out.replaceSubrange(keymapBodyRange, with: renderKeymapBody())
        return out
    }

    func renderKeymapBody() -> String {
        let i1 = baseIndent + "  "
        let i2 = i1 + "  "
        let i3 = i2 + "  "
        var s = "\n\(i1)compatible = \"zmk,keymap\";\n"
        for prop in keymapProps { s += "\(i1)\(prop);\n" }
        for layer in layers {
            s += "\n"
            let label = layer.nodeLabel.map { "\($0): " } ?? ""
            s += "\(i1)\(label)\(layer.nodeName) {\n"
            s += "\(i2)display-name = \"\(layer.displayName.replacingOccurrences(of: "\"", with: "'"))\";\n"
            if let status = layer.status { s += "\(i2)status = \"\(status)\";\n" }
            for prop in layer.extraProps { s += "\(i2)\(prop);\n" }
            if !layer.isReserved || !layer.bindings.isEmpty {
                s += "\(i2)bindings = <\n"
                for line in Self.formatBindings(layer.bindings) { s += "\(i3)\(line)\n" }
                s += "\(i2)>;\n"
            }
            s += "\(i1)};\n"
        }
        s += baseIndent
        return s
    }

    /// Lays out bindings in the same visual grid as the physical keyboard.
    public static func formatBindings(_ bindings: [KeyBinding]) -> [String] {
        let texts = bindings.map(\.text)
        guard texts.count == Adv360Layout.keyCount else {
            return stride(from: 0, to: texts.count, by: 14).map { texts[$0..<min($0 + 14, texts.count)].joined(separator: " ") }
        }
        // 20 slots per row: 0-6 left block, 7-12 middle, 13-19 right block.
        let midSlots: [[Int]] = [[], [], [8, 9, 10, 11], [9, 10], [7, 8, 9, 10, 11, 12]]
        var grid = Array(repeating: Array(repeating: "", count: 20), count: 5)
        var cursor = 0
        for (r, block) in Adv360Layout.rowBlocks.enumerated() {
            for c in 0..<block.left { grid[r][c] = texts[cursor]; cursor += 1 }
            for c in midSlots[r] { grid[r][c] = texts[cursor]; cursor += 1 }
            for c in (20 - block.right)..<20 { grid[r][c] = texts[cursor]; cursor += 1 }
        }
        let widths = (0..<20).map { c in grid.map { $0[c].count }.max() ?? 0 }
        return grid.map { row in
            var line = ""
            for c in 0..<20 where widths[c] > 0 {
                line += row[c].padding(toLength: widths[c], withPad: " ", startingAt: 0) + " "
            }
            while line.hasSuffix(" ") { line.removeLast() }
            return line
        }
    }

    // MARK: Helpers

    static func splitProp(_ raw: String) -> (String, String) {
        guard let eq = raw.firstIndex(of: "=") else { return (raw.trimmingCharacters(in: .whitespacesAndNewlines), "") }
        return (raw[..<eq].trimmingCharacters(in: .whitespacesAndNewlines),
                raw[raw.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 { t = String(t.dropFirst().dropLast()) }
        return t
    }

    static func stripAngles(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<") { t.removeFirst() }
        if t.hasSuffix(">") { t.removeLast() }
        return t
    }

    static func indent(of index: String.Index, in text: String) -> String {
        let lineStart = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        return String(text[lineStart..<index].prefix { $0 == " " || $0 == "\t" })
    }
}

// MARK: - Layer edits

extension KeymapDocument {
    /// Applies an index permutation to every layer reference (`&mo`, `&lt`, ...).
    /// `mapping[old] == nil` means the layer was removed; references become `&trans`.
    public mutating func remapLayerRefs(_ mapping: [Int: Int?]) {
        for li in layers.indices {
            for bi in layers[li].bindings.indices {
                let b = layers[li].bindings[bi]
                guard let ref = b.layerRef, let target = mapping[ref] else { continue }
                if let target {
                    layers[li].bindings[bi] = b.withLayerRef(target)
                } else if b.behavior == "lt", let key = b.param(1) {
                    layers[li].bindings[bi] = .kp(key)
                } else {
                    layers[li].bindings[bi] = .trans
                }
            }
        }
    }

    /// Index where new layers are inserted: after the last active layer, before reserved ones.
    public var insertionIndex: Int {
        layers.firstIndex(where: \.isReserved) ?? layers.count
    }

    public func uniqueNodeName(for display: String) -> String {
        let base = display.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        var name = String(base).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if name.isEmpty || name.first!.isNumber { name = "layer_" + name }
        var candidate = name, n = 2
        while layers.contains(where: { $0.nodeName == candidate }) { candidate = "\(name)_\(n)"; n += 1 }
        return candidate
    }
}

// MARK: - Minimal devicetree scanner

struct DTNode {
    var label: String?
    var name: String
    var start: String.Index
    var body: Range<String.Index>
    var depth: Int
}

enum DTItem {
    case property(String)
    case node(label: String?, name: String, body: String)
}

/// Comment- and string-aware scanner, just enough devicetree to find nodes and properties.
struct DTScanner {
    let text: String

    init(_ text: String) { self.text = text }

    /// Every node in the text, with its body range (between the braces).
    func nodes() -> [DTNode] {
        var result: [DTNode] = []
        var stack: [(header: String, start: String.Index, open: String.Index)] = []
        var statement = ""
        var statementStart = text.startIndex
        var i = text.startIndex
        var angle = 0

        while i < text.endIndex {
            if let skip = skipTrivia(at: i) { i = skip; continue }
            let ch = text[i]
            if ch == "\"" { i = skipString(at: i); statement += "\"\""; continue }
            if ch == "#" && statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isDirective(at: i) {
                // preprocessor line (#include, #define); skip to end of line
                i = text[i...].firstIndex(of: "\n") ?? text.endIndex
                continue
            }
            if ch == "<" { angle += 1 }
            if ch == ">" { angle = max(0, angle - 1) }
            if angle == 0 {
                if ch == "{" {
                    stack.append((statement, statementStart, text.index(after: i)))
                    statement = ""
                    i = text.index(after: i)
                    statementStart = i
                    continue
                }
                if ch == "}" {
                    if let top = stack.popLast() {
                        let (label, name) = Self.parseHeader(top.header)
                        let start = text.index(top.start, offsetBy: leadingWhitespace(from: top.start))
                        result.append(DTNode(label: label, name: name, start: start, body: top.open..<i, depth: stack.count))
                    }
                    statement = ""
                    i = text.index(after: i)
                    statementStart = i
                    continue
                }
                if ch == ";" {
                    statement = ""
                    i = text.index(after: i)
                    statementStart = i
                    continue
                }
            }
            if statement.isEmpty && ch.isWhitespace { statementStart = text.index(after: i) }
            statement.append(ch)
            i = text.index(after: i)
        }
        return result
    }

    /// Properties and child nodes directly inside the text (the text should be a node body).
    func topLevelItems() -> [DTItem] {
        var items: [DTItem] = []
        var depth = 0, angle = 0
        var statement = ""
        var header = ""
        var bodyStart = text.startIndex
        var i = text.startIndex

        while i < text.endIndex {
            if let skip = skipTrivia(at: i) {
                if depth == 0 { statement += " " }
                i = skip
                continue
            }
            let ch = text[i]
            if ch == "\"" {
                let end = skipString(at: i)
                if depth == 0 { statement += text[i..<end] }
                i = end
                continue
            }
            if ch == "#" && depth == 0 && statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isDirective(at: i) {
                i = text[i...].firstIndex(of: "\n") ?? text.endIndex
                continue
            }
            if depth == 0 && ch == "<" { angle += 1 }
            if depth == 0 && ch == ">" { angle = max(0, angle - 1) }
            if angle == 0 && ch == "{" {
                if depth == 0 { header = statement; bodyStart = text.index(after: i) }
                depth += 1
            } else if angle == 0 && ch == "}" {
                depth -= 1
                if depth == 0 {
                    let (label, name) = Self.parseHeader(header)
                    items.append(.node(label: label, name: name, body: String(text[bodyStart..<i])))
                    statement = ""
                    // skip the trailing ';'
                    var j = text.index(after: i)
                    while j < text.endIndex, text[j].isWhitespace { j = text.index(after: j) }
                    if j < text.endIndex, text[j] == ";" { i = text.index(after: j) } else { i = text.index(after: i) }
                    continue
                }
            } else if depth == 0 && angle == 0 && ch == ";" {
                let trimmed = Self.collapse(statement)
                if !trimmed.isEmpty { items.append(.property(trimmed)) }
                statement = ""
                i = text.index(after: i)
                continue
            }
            if depth == 0 { statement.append(ch) }
            i = text.index(after: i)
        }
        return items
    }

    private func isDirective(at i: String.Index) -> Bool {
        let rest = text[text.index(after: i)...]
        return ["include", "define", "undef", "if", "ifdef", "ifndef", "elif", "else", "endif", "pragma"]
            .contains { rest.hasPrefix($0) }
    }

    private func leadingWhitespace(from i: String.Index) -> Int {
        text[i...].prefix { $0.isWhitespace }.count
    }

    private func skipTrivia(at i: String.Index) -> String.Index? {
        let rest = text[i...]
        if rest.hasPrefix("//") { return text[i...].firstIndex(of: "\n") ?? text.endIndex }
        if rest.hasPrefix("/*") {
            return text.range(of: "*/", range: i..<text.endIndex)?.upperBound ?? text.endIndex
        }
        return nil
    }

    private func skipString(at i: String.Index) -> String.Index {
        var j = text.index(after: i)
        while j < text.endIndex {
            if text[j] == "\\" { j = text.index(j, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex; continue }
            if text[j] == "\"" { return text.index(after: j) }
            j = text.index(after: j)
        }
        return text.endIndex
    }

    /// Multi-line properties (like bindings) keep their newlines; other whitespace runs are trimmed at the ends.
    static func collapse(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseHeader(_ header: String) -> (String?, String) {
        let h = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = h.firstIndex(of: ":") {
            let label = h[..<colon].trimmingCharacters(in: .whitespaces)
            let name = h[h.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return (label, name)
        }
        return (nil, h)
    }
}
