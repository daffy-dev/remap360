import Foundation

/// Detects the keyboard in bootloader mode (a UF2 USB drive) and copies firmware onto it.
enum Flasher {
    static func bootloaderVolumes() -> Set<URL> {
        let fm = FileManager.default
        let vols = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        return Set(vols.filter { fm.fileExists(atPath: $0.appendingPathComponent("INFO_UF2.TXT").path) })
    }

    /// Waits until a bootloader drive is mounted and returns it.
    static func waitForBootloader() async throws -> URL {
        while true {
            try Task.checkCancellation()
            if let vol = bootloaderVolumes().first { return vol }
            try await Task.sleep(for: .milliseconds(600))
        }
    }

    /// Copies the file. The keyboard reboots as soon as it has the image, which often
    /// makes the copy report an error or leaves the volume half-ejected; that's expected.
    static func flash(_ file: URL, to volume: URL) async throws {
        let dest = volume.appendingPathComponent(file.lastPathComponent)
        let copyError: Error? = await Task.detached {
            do {
                let data = try Data(contentsOf: file)
                try data.write(to: dest, options: [])
                return nil
            } catch {
                return error
            }
        }.value

        // Success = the drive disappears (keyboard rebooted into the new firmware).
        for _ in 0..<40 {
            if !FileManager.default.fileExists(atPath: volume.path) || !bootloaderVolumes().contains(volume) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        if let copyError { throw copyError }
        // Drive still mounted but the copy went through; some macOS versions keep a stale mount.
    }
}
