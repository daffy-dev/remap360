import Foundation

/// The user's Adv360-Pro-ZMK config checkout.
struct Workspace: Sendable, Equatable {
    static let repoURL = "https://github.com/KinesisCorporation/Adv360-Pro-ZMK.git"
    static let defaultsKey = "workspacePath"

    let root: URL

    var configDir: URL { root.appendingPathComponent("config") }
    var keymapURL: URL { configDir.appendingPathComponent("adv360.keymap") }
    var macrosURL: URL { configDir.appendingPathComponent("macros.dtsi") }
    var firmwareDir: URL { root.appendingPathComponent("firmware") }
    var settingsResetURL: URL { root.appendingPathComponent("settings-reset.uf2") }
    var isGitRepo: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) }

    /// Contents of every `.dtsi` next to the keymap (macros, version macro, custom behaviors).
    func includeSources() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "dtsi" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    static func isValid(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("config/adv360.keymap").path)
    }

    static var defaultLocation: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Remap360/Adv360-Pro-ZMK")
    }

    static var saved: Workspace? {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        return isValid(url) ? Workspace(root: url) : nil
    }

    func remember() {
        UserDefaults.standard.set(root.path, forKey: Self.defaultsKey)
    }

    static func clone(to dest: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> Workspace {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Shell.run("git", ["clone", "--progress", repoURL, dest.path], onLine: onLine)
        return Workspace(root: dest)
    }

    static var backupsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Remap360/Backups")
    }

    /// Copies the current keymap aside before it is overwritten.
    func backupKeymap() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.backupsDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try? fm.copyItem(at: keymapURL, to: Self.backupsDir.appendingPathComponent("adv360-\(stamp).keymap"))
    }
}
