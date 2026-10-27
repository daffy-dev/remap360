import Foundation

// ZMK Studio RPC: protobuf messages (zmk-studio-messages) inside SOF/ESC/EOF framing.

public enum StudioFraming {
    public static let sof: UInt8 = 0xAB
    public static let esc: UInt8 = 0xAC
    public static let eof: UInt8 = 0xAD

    public static func encode(_ payload: Data) -> Data {
        var out = Data([sof])
        for b in payload {
            if b == sof || b == esc || b == eof { out.append(esc) }
            out.append(b)
        }
        out.append(eof)
        return out
    }

    /// Incremental decoder: feed bytes as they arrive, get complete frames back.
    public struct Decoder {
        private enum State { case idle, data, escaped }
        private var state = State.idle
        private var buffer = Data()

        public init() {}

        public mutating func feed(_ bytes: Data) -> [Data] {
            var frames: [Data] = []
            for b in bytes {
                switch state {
                case .idle:
                    if b == StudioFraming.sof { state = .data; buffer.removeAll() }
                case .data:
                    switch b {
                    case StudioFraming.sof: buffer.removeAll()   // resync on a stray start byte
                    case StudioFraming.esc: state = .escaped
                    case StudioFraming.eof: frames.append(buffer); buffer.removeAll(); state = .idle
                    default: buffer.append(b)
                    }
                case .escaped:
                    buffer.append(b)
                    state = .data
                }
            }
            return frames
        }
    }
}

// MARK: - Model

public enum StudioLockState: Sendable { case locked, unlocked }

public struct StudioBinding: Sendable, Hashable {
    public var behaviorID: Int32
    public var param1: UInt32
    public var param2: UInt32

    public init(behaviorID: Int32, param1: UInt32 = 0, param2: UInt32 = 0) {
        self.behaviorID = behaviorID
        self.param1 = param1
        self.param2 = param2
    }
}

public struct StudioLayer: Sendable, Hashable {
    public var id: UInt32
    public var name: String
    public var bindings: [StudioBinding]
}

public struct StudioKeymap: Sendable {
    public var layers: [StudioLayer]
    public var availableLayers: UInt32
    public var maxLayerNameLength: UInt32
}

public struct StudioParamValue: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case nil_
        case constant(UInt32)
        case range(Int32, Int32)
        case hidUsage(keyboardMax: UInt32, consumerMax: UInt32)
        case layerID
    }

    public var name: String
    public var kind: Kind
}

public struct StudioParamSet: Sendable, Hashable {
    public var param1: [StudioParamValue]
    public var param2: [StudioParamValue]
}

public struct StudioBehavior: Sendable, Hashable, Identifiable {
    public var id: Int32
    public var displayName: String
    public var metadata: [StudioParamSet]
}

public enum StudioError: LocalizedError, Sendable {
    case unlockRequired
    case remote(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .unlockRequired: "The keyboard is locked. Unlock it to make changes."
        case .remote(let msg): msg
        case .badResponse: "The keyboard sent a reply we couldn't understand."
        }
    }
}

// MARK: - Requests

public enum StudioRequest: Sendable {
    case getDeviceInfo, getLockState, lock
    case listBehaviors
    case behaviorDetails(Int32)
    case getKeymap
    case setBinding(layerID: UInt32, position: Int32, binding: StudioBinding)
    case checkUnsaved, save, discard
    case moveLayer(from: UInt32, to: UInt32)
    case addLayer
    case removeLayer(index: UInt32)
    case restoreLayer(id: UInt32, at: UInt32)
    case setLayerName(id: UInt32, name: String)

    public func encode(id requestID: UInt32) -> Data {
        var w = ProtoWriter()
        w.uint(1, requestID)
        switch self {
        case .getDeviceInfo: w.message(3) { $0.bool(1, true) }
        case .getLockState: w.message(3) { $0.bool(2, true) }
        case .lock: w.message(3) { $0.bool(3, true) }
        case .listBehaviors: w.message(4) { $0.bool(1, true) }
        case .behaviorDetails(let id): w.message(4) { b in b.message(2) { $0.uint(1, UInt32(bitPattern: id)) } }
        case .getKeymap: w.message(5) { $0.bool(1, true) }
        case let .setBinding(layerID, position, binding):
            w.message(5) { k in
                k.message(2) { r in
                    r.uint(1, layerID)
                    r.int(2, position)
                    r.message(3) { b in
                        b.sint(1, binding.behaviorID)
                        b.uint(2, binding.param1)
                        b.uint(3, binding.param2)
                    }
                }
            }
        case .checkUnsaved: w.message(5) { $0.bool(3, true) }
        case .save: w.message(5) { $0.bool(4, true) }
        case .discard: w.message(5) { $0.bool(5, true) }
        case let .moveLayer(from, to): w.message(5) { k in k.message(8) { $0.uint(1, from); $0.uint(2, to) } }
        case .addLayer: w.message(5) { k in k.message(9) { _ in } }
        case .removeLayer(let index): w.message(5) { k in k.message(10) { $0.uint(1, index) } }
        case let .restoreLayer(id, at): w.message(5) { k in k.message(11) { $0.uint(1, id); $0.uint(2, at) } }
        case let .setLayerName(id, name): w.message(5) { k in k.message(12) { $0.uint(1, id); $0.string(2, name) } }
        }
        return w.data
    }
}

// MARK: - Responses

public enum StudioMessage: Sendable {
    case response(id: UInt32, StudioReply)
    case lockStateChanged(StudioLockState)
    case unsavedChanged(Bool)
    case unknown
}

public enum StudioReply: Sendable {
    case ok
    case error(StudioError)
    case deviceInfo(name: String)
    case lockState(StudioLockState)
    case behaviorIDs([Int32])
    case behavior(StudioBehavior)
    case keymap(StudioKeymap)
    case bool(Bool)
    case addedLayer(index: UInt32, StudioLayer)
    case layer(StudioLayer)
}

public enum StudioDecoder {
    public static func decode(_ frame: Data) throws -> StudioMessage {
        let msg = try ProtoMessage(frame)
        if let rr = try msg.message(1) {
            return .response(id: rr.uint(1), try reply(rr))
        }
        if let n = try msg.message(2) {
            if let core = try n.message(2), core.has(1) {
                return .lockStateChanged(core.uint(1) == 1 ? .unlocked : .locked)
            }
            if let km = try n.message(5), km.has(1) {
                return .unsavedChanged(km.bool(1))
            }
        }
        return .unknown
    }

    private static func reply(_ rr: ProtoMessage) throws -> StudioReply {
        if let meta = try rr.message(2) {
            if meta.has(2) {
                switch meta.uint(2) {
                case 1: return .error(.unlockRequired)
                case 2: return .error(.remote("This keyboard's firmware doesn't support that request."))
                default: return .error(.remote("The keyboard reported an error (\(meta.uint(2)))."))
                }
            }
            return .ok
        }
        if let core = try rr.message(3) {
            if let info = try core.message(1) { return .deviceInfo(name: info.string(1)) }
            if core.has(2) || core.fields.isEmpty { return .lockState(core.uint(2) == 1 ? .unlocked : .locked) }
            return .ok
        }
        if let beh = try rr.message(4) {
            if let list = try beh.message(1) {
                return .behaviorIDs(try list.uints(1).map { Int32(bitPattern: $0) })
            }
            if let d = try beh.message(2) {
                let sets = try d.messages(3).map { set in
                    StudioParamSet(param1: try set.messages(1).map(paramValue), param2: try set.messages(2).map(paramValue))
                }
                return .behavior(StudioBehavior(id: Int32(bitPattern: d.uint(1)), displayName: d.string(2), metadata: sets))
            }
            return .behaviorIDs([])
        }
        if let km = try rr.message(5) {
            if let keymap = try km.message(1) { return .keymap(try parseKeymap(keymap)) }
            if km.has(2) {
                switch km.uint(2) {
                case 0: return .ok
                case 1: return .error(.remote("That key position doesn't exist."))
                case 2: return .error(.remote("The keyboard doesn't have that behavior."))
                default: return .error(.remote("The keyboard rejected those settings for this key."))
                }
            }
            if km.has(3) { return .bool(km.bool(3)) }
            if let save = try km.message(4) {
                if save.has(2) {
                    return .error(.remote(save.uint(2) == 3 ? "The keyboard is out of storage space." : "The keyboard couldn't save the changes."))
                }
                return .ok
            }
            if km.has(5) { return .ok }
            if let move = try km.message(8) {
                if let k = try move.message(1) { return .keymap(try parseKeymap(k)) }
                return .error(.remote("Couldn't move that layer."))
            }
            if let add = try km.message(9) {
                if let ok = try add.message(1), let layer = try ok.message(2) {
                    return .addedLayer(index: ok.uint(1), try parseLayer(layer))
                }
                return .error(.remote(add.uint(2) == 2 ? "No free layer slots left on the keyboard." : "Couldn't add a layer."))
            }
            if let remove = try km.message(10) {
                return remove.has(2) ? .error(.remote("Couldn't remove that layer.")) : .ok
            }
            if let restore = try km.message(11) {
                if let layer = try restore.message(1) { return .layer(try parseLayer(layer)) }
                return .error(.remote("Couldn't restore that layer."))
            }
            if km.has(12) {
                return km.uint(12) == 0 ? .ok : .error(.remote("Couldn't rename that layer."))
            }
            // Empty keymap response = a oneof holding its default value (e.g. set_layer_binding OK).
            return .ok
        }
        return .ok
    }

    private static func paramValue(_ m: ProtoMessage) throws -> StudioParamValue {
        let kind: StudioParamValue.Kind
        if m.has(3) {
            kind = .constant(m.uint(3))
        } else if let r = try m.message(4) {
            kind = .range(r.int(1), r.int(2))
        } else if let h = try m.message(5) {
            kind = .hidUsage(keyboardMax: h.uint(1), consumerMax: h.uint(2))
        } else if m.has(6) {
            kind = .layerID
        } else {
            kind = .nil_
        }
        return StudioParamValue(name: m.string(1), kind: kind)
    }

    static func parseLayer(_ m: ProtoMessage) throws -> StudioLayer {
        StudioLayer(
            id: m.uint(1),
            name: m.string(2),
            bindings: try m.messages(3).map { StudioBinding(behaviorID: $0.sint(1), param1: $0.uint(2), param2: $0.uint(3)) }
        )
    }

    static func parseKeymap(_ m: ProtoMessage) throws -> StudioKeymap {
        StudioKeymap(layers: try m.messages(1).map(parseLayer), availableLayers: m.uint(2), maxLayerNameLength: m.uint(3))
    }
}
