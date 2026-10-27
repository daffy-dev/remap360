import Foundation
import Observation
import Remap360Core

/// Finds a ZMK Studio keyboard on USB, keeps the connection alive and mirrors its keymap.
@MainActor
@Observable
final class LiveController {
    enum Status: Equatable {
        case searching
        case connecting
        case locked
        case loading
        case ready
    }

    private(set) var status: Status = .searching
    private(set) var deviceName: String?
    private(set) var keymap: LiveKeymap?
    private(set) var unsaved = false

    /// Called whenever the keymap on the keyboard changed (loaded, edited, reverted).
    @ObservationIgnored var onKeymapChanged: (() -> Void)?

    @ObservationIgnored private var connection: StudioConnection?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var failedPaths: [String: Date] = [:]

    var isConnected: Bool { status != .searching && status != .connecting }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func tick() async {
        switch status {
        case .searching:
            await scan()
        case .locked:
            // Fallback in case the unlock notification was missed.
            if case .lockState(.unlocked)? = try? await connection?.call(.getLockState, timeout: .seconds(2)) {
                await load()
            }
        default:
            break
        }
    }

    private func scan() async {
        let now = Date()
        for candidate in SerialPort.candidates() {
            if let failed = failedPaths[candidate.path], now.timeIntervalSince(failed) < 8 { continue }
            status = .connecting
            let conn = StudioConnection(path: candidate.path)
            do {
                try conn.open()
                guard case .deviceInfo(let name) = try await conn.call(.getDeviceInfo, timeout: .milliseconds(1500)) else {
                    throw StudioError.badResponse
                }
                attach(conn, name: name.isEmpty ? (candidate.product ?? "Keyboard") : name)
                return
            } catch {
                conn.close()
                failedPaths[candidate.path] = now
            }
        }
        status = .searching
    }

    private func attach(_ conn: StudioConnection, name: String) {
        connection = conn
        deviceName = name
        conn.onNotification = { [weak self] message in
            Task { @MainActor in self?.handle(message) }
        }
        conn.onClose = { [weak self] in
            Task { @MainActor in self?.detach() }
        }
        status = .locked
        Task {
            if case .lockState(.unlocked)? = try? await conn.call(.getLockState) {
                await load()
            }
        }
    }

    private func detach() {
        connection = nil
        deviceName = nil
        keymap = nil
        unsaved = false
        status = .searching
        onKeymapChanged?()
    }

    func disconnect() {
        connection?.close()
    }

    private func handle(_ message: StudioMessage) {
        switch message {
        case .lockStateChanged(.unlocked):
            if status == .locked { Task { await load() } }
        case .lockStateChanged(.locked):
            status = .locked
        case .unsavedChanged(let value):
            unsaved = value
        default:
            break
        }
    }

    /// Reads behaviors and the keymap from the keyboard.
    func load() async {
        guard let connection else { return }
        status = .loading
        do {
            guard case .behaviorIDs(let ids) = try await connection.call(.listBehaviors) else { throw StudioError.badResponse }
            var behaviors: [StudioBehavior] = []
            for id in ids {
                if case .behavior(let b) = try await connection.call(.behaviorDetails(id)) { behaviors.append(b) }
            }
            guard case .keymap(let km) = try await connection.call(.getKeymap) else { throw StudioError.badResponse }
            if case .bool(let dirty) = try await connection.call(.checkUnsaved) { unsaved = dirty }
            keymap = LiveKeymap(keymap: km, behaviors: behaviors)
            status = .ready
            onKeymapChanged?()
        } catch StudioError.unlockRequired {
            status = .locked
        } catch {
            status = .locked
        }
    }

    // MARK: Editing

    private func requireConnection() throws -> StudioConnection {
        guard let connection, status == .ready else { throw StudioConnection.ConnectionError.closed }
        return connection
    }

    func setBinding(_ binding: KeyBinding, layer: Int, key: Int) async throws {
        let conn = try requireConnection()
        guard var km = keymap, layer < km.layers.count else { return }
        let studio = try km.studioBinding(binding)
        _ = try await conn.call(.setBinding(layerID: km.layers[layer].id, position: Int32(key), binding: studio))
        km.layers[layer].bindings[key] = studio
        keymap = km
        unsaved = true
        onKeymapChanged?()
    }

    func save() async throws {
        _ = try await requireConnection().call(.save, timeout: .seconds(10))
        unsaved = false
    }

    func discard() async throws {
        _ = try await requireConnection().call(.discard)
        unsaved = false
        await load()
    }

    @discardableResult
    func addLayer(named name: String) async throws -> Int {
        let conn = try requireConnection()
        guard case .addedLayer(let index, var layer) = try await conn.call(.addLayer) else { throw StudioError.badResponse }
        if !name.isEmpty, (try? await conn.call(.setLayerName(id: layer.id, name: name))) != nil { layer.name = name }
        keymap?.layers.insert(layer, at: min(Int(index), keymap?.layers.count ?? 0))
        unsaved = true
        onKeymapChanged?()
        return Int(index)
    }

    func removeLayer(at index: Int) async throws {
        _ = try await requireConnection().call(.removeLayer(index: UInt32(index)))
        keymap?.layers.remove(at: index)
        unsaved = true
        onKeymapChanged?()
    }

    func moveLayer(from: Int, to: Int) async throws {
        guard case .keymap(let km) = try await requireConnection().call(.moveLayer(from: UInt32(from), to: UInt32(to))) else {
            throw StudioError.badResponse
        }
        keymap?.layers = km.layers
        unsaved = true
        onKeymapChanged?()
    }

    func renameLayer(at index: Int, to name: String) async throws {
        guard let km = keymap, index < km.layers.count else { return }
        let limited = String(name.prefix(Int(max(km.maxLayerNameLength, 1))))
        _ = try await requireConnection().call(.setLayerName(id: km.layers[index].id, name: limited))
        keymap?.layers[index].name = limited
        unsaved = true
        onKeymapChanged?()
    }
}
