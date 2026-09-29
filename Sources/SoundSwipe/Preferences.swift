import Foundation

struct AppMix: Codable, Equatable {
    /// 1 is unchanged; up to `maxVolume` boosts through the DSP soft limiter.
    static let maxVolume: Float = 2
    var volume: Float = 1
    var muted = false
    var outputUID: String? = nil
    var effectiveGain: Float { muted ? 0 : min(Self.maxVolume, max(0, volume.isFinite ? volume : 1)) }
    var needsMixing: Bool { muted || abs(effectiveGain - 1) > 0.001 || outputUID != nil }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var repository: URL? { (Bundle.main.object(forInfoDictionaryKey: "RepositoryURL") as? String).flatMap { Preferences.profileURL($0, hosts: ["github.com"]) } }
}

struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case panel, mute, quieter, louder, nextOutput
    var id: String { rawValue }
    var title: String {
        switch self {
        case .panel: "Show SoundSwipe"
        case .mute: "Mute / unmute output"
        case .quieter: "Volume down"
        case .louder: "Volume up"
        case .nextOutput: "Next output device"
        }
    }
}

final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var mixes: [String: AppMix] { didSet { save(mixes, key: "mixes") } }
    @Published var shortcuts: [String: ShortcutBinding] { didSet { save(shortcuts, key: "shortcuts") } }
    @Published var github: String { didSet { defaults.set(github, forKey: "developer.github") } }
    @Published var twitter: String { didSet { defaults.set(twitter, forKey: "developer.twitter") } }
    @Published var mixAtLaunch: Bool { didSet { defaults.set(mixAtLaunch, forKey: "mixAtLaunch") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mixes = defaults.data(forKey: "mixes").flatMap { try? JSONDecoder().decode([String: AppMix].self, from: $0) } ?? [:]
        shortcuts = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: ShortcutBinding].self, from: $0) } ?? [:]
        github = defaults.string(forKey: "developer.github") ?? Bundle.main.object(forInfoDictionaryKey: "DeveloperGitHub") as? String ?? ""
        twitter = defaults.string(forKey: "developer.twitter") ?? Bundle.main.object(forInfoDictionaryKey: "DeveloperTwitter") as? String ?? ""
        mixAtLaunch = defaults.bool(forKey: "mixAtLaunch")
    }
    private func save<T: Encodable>(_ value: T, key: String) { if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } }
    static func profileURL(_ text: String, hosts: Set<String>) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host?.lowercased(), hosts.contains(host), url.user == nil, url.password == nil, url.port == nil, url.path.count > 1 else { return nil }
        return url
    }
}
