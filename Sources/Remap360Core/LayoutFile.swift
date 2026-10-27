import Foundation

/// A whole keyboard layout as a small, human-readable JSON file (bindings in ZMK syntax),
/// used for export/import and automatic backups.
public struct LayoutFile: Codable, Sendable, Equatable {
    public struct LayerEntry: Codable, Sendable, Equatable {
        public var name: String
        public var bindings: [String]
    }

    public var format = "remap360-layout"
    public var version = 1
    public var keyboard: String
    public var savedAt: Date
    public var layers: [LayerEntry]

    public init(keyboard: String, layers: [Layer], savedAt: Date = .now) {
        self.keyboard = keyboard
        self.savedAt = savedAt
        self.layers = layers.map { LayerEntry(name: $0.displayName, bindings: $0.bindings.map(\.text)) }
    }

    public enum ReadError: LocalizedError {
        case notALayout
        case wrongKeyCount(layer: String, count: Int)

        public var errorDescription: String? {
            switch self {
            case .notALayout: "That file isn't a Remap360 layout."
            case let .wrongKeyCount(layer, count): "Layer “\(layer)” has \(count) keys, but the Advantage360 has \(Adv360Layout.keyCount)."
            }
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LayoutFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(LayoutFile.self, from: data), file.format == "remap360-layout" else {
            throw ReadError.notALayout
        }
        for layer in file.layers where layer.bindings.count != Adv360Layout.keyCount {
            throw ReadError.wrongKeyCount(layer: layer.name, count: layer.bindings.count)
        }
        return file
    }

    /// Bindings for one layer, parsed back into editor form.
    public func bindings(ofLayer i: Int) -> [KeyBinding] {
        layers[i].bindings.map { BindingParser.parse($0).first ?? .trans }
    }
}
