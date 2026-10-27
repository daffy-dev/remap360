import AppKit
import Foundation

struct BuiltFirmware: Sendable {
    var left: URL?
    var right: URL?
}

/// Builds firmware locally with the same Docker image the official Makefile uses.
enum FirmwareBuilder {
    static let image = "remap360-zmk"

    static func ensureDocker(onLine: @escaping @Sendable (String) -> Void) async throws {
        guard Shell.which("docker") != nil else {
            throw BuildError.dockerMissing
        }
        if (try? await Shell.run("docker", ["info", "--format", "{{.ServerVersion}}"])) != nil { return }
        onLine("Starting Docker Desktop…")
        _ = try? await Shell.run("open", ["-a", "Docker"])
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(2))
            if (try? await Shell.run("docker", ["info", "--format", "{{.ServerVersion}}"])) != nil { return }
        }
        throw BuildError.dockerNotRunning
    }

    static func build(
        _ ws: Workspace, right: Bool, onLine: @escaping @Sendable (String) -> Void
    ) async throws -> BuiltFirmware {
        try await ensureDocker(onLine: onLine)
        let fm = FileManager.default
        try fm.createDirectory(at: ws.firmwareDir, withIntermediateDirectories: true)

        let started = Date()
        let stamp = Self.timestamp()
        var commit = "local"
        if ws.isGitRepo {
            commit = (try? await Shell.run("git", ["rev-parse", "--short", "HEAD"], cwd: ws.root))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "local"
            // Same as `make`: stamp the version macro, restored afterwards.
            _ = try? await Shell.run("bash", ["bin/get_version_local.sh", "clique"], cwd: ws.root)
        }
        defer {
            if ws.isGitRepo {
                Task { _ = try? await Shell.run("git", ["checkout", "config/version.dtsi"], cwd: ws.root) }
            }
        }

        onLine("▸ Preparing build image (first time downloads the ZMK toolchain, ~5–10 min)")
        try await Shell.run("docker", ["build", "--tag", image, "--file", "Dockerfile", "."], cwd: ws.root, onLine: onLine)

        onLine("▸ Compiling firmware" + (right ? " for both halves" : " for the left half"))
        try await Shell.run("docker", [
            "run", "--rm",
            "-v", "\(ws.firmwareDir.path):/app/firmware",
            "-v", "\(ws.configDir.path):/app/config:ro",
            "-e", "TIMESTAMP=\(stamp)",
            "-e", "COMMIT=\(commit)",
            "-e", "BUILD_RIGHT=\(right)",
            image,
        ], cwd: ws.root, onLine: onLine)

        let files = (try? fm.contentsOfDirectory(at: ws.firmwareDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func newest(_ side: String) -> URL? {
            files.filter { $0.pathExtension == "uf2" && $0.lastPathComponent.contains("-\(side)") }
                .filter { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast >= started.addingTimeInterval(-5) }
                .max { $0.lastPathComponent < $1.lastPathComponent }
        }
        let result = BuiltFirmware(left: newest("left"), right: right ? newest("right") : nil)
        guard result.left != nil else { throw BuildError.noOutput }
        onLine("✓ Built \([result.left, result.right].compactMap { $0?.lastPathComponent }.joined(separator: ", "))")
        return result
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: .now)
    }

    enum BuildError: LocalizedError {
        case dockerMissing, dockerNotRunning, noOutput

        var errorDescription: String? {
            switch self {
            case .dockerMissing: "Docker isn't installed. Install Docker Desktop (or `brew install --cask docker`) and try again."
            case .dockerNotRunning: "Docker Desktop didn't start. Open it manually and try again."
            case .noOutput: "The build finished but no firmware file was produced. Check the log for errors."
            }
        }
    }
}
