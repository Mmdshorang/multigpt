import Foundation

/// Checks GitHub releases for new versions.
enum UpdateChecker {
    struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
    }

    static let repository = "mohamadhosein/multicodex"

    static func checkForUpdate(currentVersion: String) async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

        guard latest != currentVersion else { return nil }
        guard isVersion(latest, newerThan: currentVersion) else { return nil }

        return release
    }

    private static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(parts1.count, parts2.count) {
            let a = i < parts1.count ? parts1[i] : 0
            let b = i < parts2.count ? parts2[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}
