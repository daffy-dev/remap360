import Foundation

/// Watches Kinesis' official firmware repo for real firmware changes (not docs or CI tweaks).
/// A firmware change means a commit touching the ZMK version (`config/west.yml`) or the board files.
enum FirmwareUpdates {
    struct Release: Equatable {
        var date: Date
        var sha: String
        var title: String
        var url: URL
    }

    static let repo = "KinesisCorporation/Adv360-Pro-ZMK"
    static let watchedPaths = ["config/west.yml", "config/boards"]

    private static let seenKey = "firmwareLastSeenDate"
    private static let checkedKey = "firmwareLastCheck"

    /// Newest firmware-relevant commit, or nil when GitHub can't be reached.
    static func latest() async -> Release? {
        var newest: Release?
        for path in watchedPaths {
            var components = URLComponents(string: "https://api.github.com/repos/\(repo)/commits")!
            components.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "per_page", value: "1")]
            var request = URLRequest(url: components.url!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let commits = try? JSONDecoder().decode([Commit].self, from: data),
                  let c = commits.first,
                  let date = ISO8601DateFormatter().date(from: c.commit.committer.date),
                  let url = URL(string: c.html_url) else { continue }
            let release = Release(date: date, sha: String(c.sha.prefix(7)),
                                  title: c.commit.message.components(separatedBy: "\n").first ?? "", url: url)
            if newest == nil || release.date > newest!.date { newest = release }
        }
        return newest
    }

    /// The newest firmware the user has seen (installed or dismissed). On first run we assume the
    /// keyboard is current, since the Advantage360 ships with and updates to the latest release.
    static var lastSeen: Date? {
        get { UserDefaults.standard.object(forKey: seenKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    static var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: checkedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: checkedKey) }
    }

    private struct Commit: Decodable {
        struct Inner: Decodable {
            struct Person: Decodable { let date: String }
            let committer: Person
            let message: String
        }
        let sha: String
        let html_url: String
        let commit: Inner
    }
}
