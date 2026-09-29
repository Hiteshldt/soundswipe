import Foundation

struct AppMix: Codable, Equatable {
    /// 1 is unchanged; up to `maxVolume` boosts through the DSP soft limiter.
    static let maxVolume: Float = 2
    static let eqRange: Float = 12
    var volume: Float = 1
    var muted = false
    var outputUID: String? = nil
    /// Bass (100 Hz shelf), mid (1 kHz), treble (8 kHz shelf) in dB.
    var eq: [Float] = [0, 0, 0]
    /// -1 left … 1 right.
    var balance: Float = 0
    init(volume: Float = 1, muted: Bool = false, outputUID: String? = nil) { self.volume = volume; self.muted = muted; self.outputUID = outputUID }
    // Decode leniently so settings saved by earlier versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        outputUID = try c.decodeIfPresent(String.self, forKey: .outputUID)
        let bands = try c.decodeIfPresent([Float].self, forKey: .eq) ?? []
        eq = bands.count == 3 ? bands : [0, 0, 0]
        balance = try c.decodeIfPresent(Float.self, forKey: .balance) ?? 0
    }
    var effectiveGain: Float { muted ? 0 : min(Self.maxVolume, max(0, volume.isFinite ? volume : 1)) }
    var eqActive: Bool { eq.contains { abs($0) > 0.01 } }
    var needsMixing: Bool { muted || abs(effectiveGain - 1) > 0.001 || outputUID != nil || eqActive || abs(balance) > 0.01 }
}

enum EQPreset: String, CaseIterable, Identifiable {
    case flat, bass, voice, treble, loudness, lessBass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: "Flat"
        case .bass: "Bass Boost"
        case .voice: "Voice Clarity"
        case .treble: "Treble Boost"
        case .loudness: "Loudness"
        case .lessBass: "Reduce Bass"
        }
    }
    var bands: [Float] {
        switch self {
        case .flat: [0, 0, 0]
        case .bass: [6, 0, 0]
        case .voice: [-5, 3, 2]
        case .treble: [0, 0, 5]
        case .loudness: [5, -1, 4]
        case .lessBass: [-8, 0, 0]
        }
    }
    static func matching(_ bands: [Float]) -> EQPreset? { allCases.first { $0.bands == bands } }
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
    // Append new cases only: hot key IDs are derived from case order.
    case panel, mute, quieter, louder, nextOutput, micMute
    var id: String { rawValue }
    var title: String {
        switch self {
        case .panel: "Show SoundSwipe"
        case .mute: "Mute / unmute output"
        case .quieter: "Volume down"
        case .louder: "Volume up"
        case .nextOutput: "Next output device"
        case .micMute: "Mute / unmute microphone"
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
