import Darwin
import Foundation
import IOKit
import IOKit.serial

/// A raw USB serial (CDC ACM) port, read with a dispatch source.
final class SerialPort: @unchecked Sendable {
    let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "remap360.serial")

    var onData: (@Sendable (Data) -> Void)?
    var onClose: (@Sendable () -> Void)?

    init(path: String) { self.path = path }

    func open() throws {
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Exclusive access so two apps (e.g. ZMK Studio) don't fight over the port.
        _ = ioctl(fd, TIOCEXCL)
        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B115200))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(fd, TCSANOW, &t)
        tcflush(fd, TCIOFLUSH)

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.readAvailable() }
        src.setCancelHandler { [fd] in Darwin.close(fd) }
        source = src
        src.resume()
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        if n > 0 {
            onData?(Data(buf[0..<n]))
        } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
            close()
        }
    }

    func write(_ data: Data) throws {
        try queue.sync {
            guard fd >= 0 else { throw POSIXError(.ENXIO) }
            var offset = 0
            let bytes = [UInt8](data)
            var attempts = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    offset += n
                } else if errno == EAGAIN && attempts < 200 {
                    attempts += 1
                    usleep(2000)
                } else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }
    }

    func close() {
        guard let source else { return }
        self.source = nil
        source.cancel()
        fd = -1
        onClose?()
    }

    // MARK: Discovery

    struct Candidate {
        var path: String
        var product: String?
    }

    /// USB modem ports, with the USB product name when IOKit knows it.
    static func candidates() -> [Candidate] {
        var result: [Candidate] = []
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return result }
        (matching as NSMutableDictionary)[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String, path.contains("usbmodem") else { continue }
            let product = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "USB Product Name" as CFString, kCFAllocatorDefault,
                                                          IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
            result.append(Candidate(path: path, product: product))
        }
        // Likely keyboards first.
        return result.sorted { a, b in score(a) > score(b) }
    }

    private static func score(_ c: Candidate) -> Int {
        guard let p = c.product?.lowercased() else { return 0 }
        if p.contains("360") || p.contains("adv") || p.contains("kinesis") { return 2 }
        if p.contains("zmk") || p.contains("keyboard") { return 1 }
        return 0
    }
}
