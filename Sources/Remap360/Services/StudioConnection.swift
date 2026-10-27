import Foundation
import Remap360Core

/// Request/response RPC with a ZMK Studio keyboard over a serial port.
final class StudioConnection: @unchecked Sendable {
    enum ConnectionError: LocalizedError {
        case timeout, closed

        var errorDescription: String? {
            switch self {
            case .timeout: "The keyboard didn't answer."
            case .closed: "The keyboard was disconnected."
            }
        }
    }

    let port: SerialPort
    private let lock = NSLock()
    private var decoder = StudioFraming.Decoder()
    private var pending: [UInt32: CheckedContinuation<StudioReply, Error>] = [:]
    private var nextID: UInt32 = 1
    private var closed = false

    var onNotification: (@Sendable (StudioMessage) -> Void)?
    var onClose: (@Sendable () -> Void)?

    init(path: String) {
        port = SerialPort(path: path)
    }

    func open() throws {
        port.onData = { [weak self] data in self?.received(data) }
        port.onClose = { [weak self] in self?.didClose() }
        try port.open()
    }

    func close() { port.close() }

    private func received(_ data: Data) {
        lock.lock()
        let frames = decoder.feed(data)
        lock.unlock()
        for frame in frames {
            guard let message = try? StudioDecoder.decode(frame) else { continue }
            switch message {
            case .response(let id, let reply):
                lock.lock()
                let cont = pending.removeValue(forKey: id)
                lock.unlock()
                cont?.resume(returning: reply)
            case .lockStateChanged, .unsavedChanged:
                onNotification?(message)
            case .unknown:
                break
            }
        }
    }

    private func didClose() {
        lock.lock()
        closed = true
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        for (_, c) in waiting { c.resume(throwing: ConnectionError.closed) }
        onClose?()
    }

    /// Sends a request and waits for its reply. Device errors are thrown.
    func call(_ request: StudioRequest, timeout: Duration = .seconds(4)) async throws -> StudioReply {
        let id: UInt32? = lock.withLock {
            if closed { return nil }
            defer { nextID &+= 1 }
            return nextID
        }
        guard let id else { throw ConnectionError.closed }

        let reply: StudioReply = try await withCheckedThrowingContinuation { cont in
            lock.withLock { pending[id] = cont }
            do {
                try port.write(StudioFraming.encode(request.encode(id: id)))
            } catch {
                lock.withLock { pending.removeValue(forKey: id) }?.resume(throwing: error)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                self.lock.withLock { self.pending.removeValue(forKey: id) }?.resume(throwing: ConnectionError.timeout)
            }
        }
        if case .error(let e) = reply { throw e }
        return reply
    }
}
