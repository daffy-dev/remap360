import Foundation

/// Minimal protobuf wire-format support — just what the ZMK Studio protocol needs.
public struct ProtoWriter {
    public private(set) var data = Data()

    public init() {}

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, _ wireType: UInt64) {
        varint(UInt64(field) << 3 | wireType)
    }

    public mutating func uint(_ field: Int, _ value: UInt32) {
        tag(field, 0)
        varint(UInt64(value))
    }

    public mutating func int(_ field: Int, _ value: Int32) {
        tag(field, 0)
        varint(UInt64(bitPattern: Int64(value)))
    }

    public mutating func sint(_ field: Int, _ value: Int32) {
        tag(field, 0)
        varint(UInt64(UInt32(bitPattern: (value << 1) ^ (value >> 31))))
    }

    public mutating func bool(_ field: Int, _ value: Bool) {
        tag(field, 0)
        varint(value ? 1 : 0)
    }

    public mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    public mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    public mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var sub = ProtoWriter()
        build(&sub)
        bytes(field, sub.data)
    }
}

public enum ProtoError: Error {
    case truncated
    case unsupportedWireType(Int)
}

/// A decoded message: every field number maps to its raw values in order.
public struct ProtoMessage {
    public enum Value {
        case varint(UInt64)
        case bytes(Data)
        case fixed(UInt64)
    }

    public private(set) var fields: [Int: [Value]] = [:]

    public init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var i = 0

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard i < bytes.count else { throw ProtoError.truncated }
                let b = bytes[i]
                i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { throw ProtoError.truncated }
            }
        }

        while i < bytes.count {
            let key = try readVarint()
            let field = Int(key >> 3)
            let wire = Int(key & 7)
            let value: Value
            switch wire {
            case 0:
                value = .varint(try readVarint())
            case 1:
                guard i + 8 <= bytes.count else { throw ProtoError.truncated }
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(bytes[i + k]) << (8 * UInt64(k)) }
                i += 8
                value = .fixed(v)
            case 2:
                let len = Int(try readVarint())
                guard len >= 0, i + len <= bytes.count else { throw ProtoError.truncated }
                value = .bytes(Data(bytes[i..<(i + len)]))
                i += len
            case 5:
                guard i + 4 <= bytes.count else { throw ProtoError.truncated }
                var v: UInt64 = 0
                for k in 0..<4 { v |= UInt64(bytes[i + k]) << (8 * UInt64(k)) }
                i += 4
                value = .fixed(v)
            default:
                throw ProtoError.unsupportedWireType(wire)
            }
            fields[field, default: []].append(value)
        }
    }

    public func has(_ field: Int) -> Bool { fields[field] != nil }

    public func uint(_ field: Int) -> UInt32 {
        if case .varint(let v)? = fields[field]?.last { return UInt32(truncatingIfNeeded: v) }
        return 0
    }

    public func int(_ field: Int) -> Int32 {
        if case .varint(let v)? = fields[field]?.last { return Int32(truncatingIfNeeded: Int64(bitPattern: v)) }
        return 0
    }

    public func sint(_ field: Int) -> Int32 {
        let raw = uint(field)
        return Int32(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
    }

    public func bool(_ field: Int) -> Bool { uint(field) != 0 }

    public func string(_ field: Int) -> String {
        if case .bytes(let d)? = fields[field]?.last { return String(decoding: d, as: UTF8.self) }
        return ""
    }

    public func message(_ field: Int) throws -> ProtoMessage? {
        guard case .bytes(let d)? = fields[field]?.last else { return nil }
        return try ProtoMessage(d)
    }

    public func messages(_ field: Int) throws -> [ProtoMessage] {
        try (fields[field] ?? []).compactMap { v in
            if case .bytes(let d) = v { return try ProtoMessage(d) }
            return nil
        }
    }

    /// Repeated uint32, accepting both packed and unpacked encodings.
    public func uints(_ field: Int) throws -> [UInt32] {
        var out: [UInt32] = []
        for v in fields[field] ?? [] {
            switch v {
            case .varint(let x):
                out.append(UInt32(truncatingIfNeeded: x))
            case .bytes(let d):
                // Re-parse the packed payload as a sequence of varints.
                let bytes = [UInt8](d)
                var i = 0
                while i < bytes.count {
                    var result: UInt64 = 0, shift: UInt64 = 0
                    while true {
                        guard i < bytes.count else { throw ProtoError.truncated }
                        let b = bytes[i]
                        i += 1
                        result |= UInt64(b & 0x7F) << shift
                        if b & 0x80 == 0 { break }
                        shift += 7
                    }
                    out.append(UInt32(truncatingIfNeeded: result))
                }
            case .fixed(let x):
                out.append(UInt32(truncatingIfNeeded: x))
            }
        }
        return out
    }
}
