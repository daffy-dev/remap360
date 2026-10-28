import Foundation
import Remap360Core

/// Checks GitHub Releases for a newer Remap360 than the one running.
enum AppUpdates {
    struct Release: Equatable {
        var version: AppVersion
        var name: String
        var pageURL: URL
        var downloadURL: URL
    }

    static let repo = "daffy-dev/remap360"

    private static let skippedKey = "skippedAppVersion"

    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    /// The latest published release, or nil when GitHub can't be reached.
    static func latest() async -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let version = AppVersion(r.tag_name),
              let page = URL(string: r.html_url) else { return nil }
        let dmg = r.assets.first { $0.name.hasSuffix(".dmg") }.flatMap { URL(string: $0.browser_download_url) }
        return Release(version: version, name: r.name ?? "Remap360 \(version)", pageURL: page, downloadURL: dmg ?? page)
    }

    /// A version the user chose to skip; it isn't offered again (newer ones are).
    static var skipped: AppVersion? {
        get { UserDefaults.standard.string(forKey: skippedKey).flatMap(AppVersion.init) }
        set { UserDefaults.standard.set(newValue?.description, forKey: skippedKey) }
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let name: String?
        let html_url: String
        let assets: [Asset]
    }
}
