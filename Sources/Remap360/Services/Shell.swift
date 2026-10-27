import Foundation

enum ShellError: LocalizedError {
    case failed(command: String, status: Int32, tail: String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .failed(let command, let status, let tail):
            "`\(command)` exited with status \(status).\n\(tail)"
        case .notFound(let tool):
            "Couldn't find `\(tool)`."
        }
    }
}

/// Runs command-line tools with a sensible PATH (GUI apps don't inherit the shell's).
enum Shell {
    static let searchPath = [
        "/usr/local/bin", "/opt/homebrew/bin", "/Applications/Docker.app/Contents/Resources/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        env["PATH"] = (searchPath + existing).joined(separator: ":")
        return env
    }

    static func which(_ tool: String) -> String? {
        for dir in searchPath {
            let path = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Runs a tool and streams every output line to `onLine`. Throws if the exit status is non-zero.
    @discardableResult
    static func run(
        _ tool: String, _ args: [String], cwd: URL? = nil, env extra: [String: String] = [:],
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        guard let exe = tool.hasPrefix("/") ? tool : which(tool) else { throw ShellError.notFound(tool) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = environment.merging(extra) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = LineCollector(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            collector.feed(data)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                process.terminationHandler = { p in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                    collector.feed(rest)
                    collector.flush()
                    let output = collector.output
                    if p.terminationStatus == 0 {
                        cont.resume(returning: output)
                    } else {
                        let tail = output.split(separator: "\n").suffix(12).joined(separator: "\n")
                        cont.resume(throwing: ShellError.failed(
                            command: ([tool] + args).joined(separator: " "), status: p.terminationStatus, tail: tail))
                    }
                }
                do { try process.run() } catch { cont.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private(set) var output = ""
    let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let nl = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            emit(lineData)
        }
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        if !buffer.isEmpty { emit(buffer); buffer.removeAll() }
    }

    private func emit(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self)
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        output += line + "\n"
        onLine(line)
    }
}
