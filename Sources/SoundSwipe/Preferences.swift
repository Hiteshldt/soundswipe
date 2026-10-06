import Foundation

struct AppMix: Codable, Equatable {
    /// 1 is unchanged; up to `maxVolume` boosts through the DSP soft limiter.
    static let maxVolume: Float = 4
    static let eqRange: Float = 12
    static let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let flatEQ = [Float](repeating: 0, count: 10)
    var volume: Float = 1
    var muted = false
    var outputUID: String? = nil
    /// Gain in dB for each of `eqFrequencies`.
    var eq: [Float] = Self.flatEQ
    /// Bypasses the EQ without losing its bands.
    var eqEnabled = true
    /// -1 left … 1 right.
    var balance: Float = 0
    init(volume: Float = 1, muted: Bool = false, outputUID: String? = nil) { self.volume = volume; self.muted = muted; self.outputUID = outputUID }
    // Decode leniently so settings saved by earlier versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = min(Self.maxVolume, max(0, try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1))
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        outputUID = try c.decodeIfPresent(String.self, forKey: .outputUID)
        eq = Self.normalizedEQ(try c.decodeIfPresent([Float].self, forKey: .eq) ?? [])
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? true
        balance = min(1, max(-1, try c.decodeIfPresent(Float.self, forKey: .balance) ?? 0))
    }
    /// 0.3.x stored bass/mid/treble; spread those across the matching octave bands.
    static func normalizedEQ(_ bands: [Float]) -> [Float] {
        switch bands.count {
        case 10: bands.map { min(eqRange, max(-eqRange, $0.isFinite ? $0 : 0)) }
        case 3: normalizedEQ([bands[0], bands[0], bands[0] * 0.5, 0, bands[1] * 0.5, bands[1], bands[1] * 0.5, bands[2] * 0.5, bands[2], bands[2]])
        default: flatEQ
        }
    }
    var effectiveGain: Float { muted ? 0 : min(Self.maxVolume, max(0, volume.isFinite ? volume : 1)) }
    /// Band gains the DSP should apply right now.
    var activeEQ: [Float] { eqEnabled ? eq : Self.flatEQ }
    var eqActive: Bool { activeEQ.contains { abs($0) > 0.01 } }
    var needsMixing: Bool { muted || abs(effectiveGain - 1) > 0.001 || outputUID != nil || eqActive || abs(balance) > 0.01 }
}

/// Graphic EQ presets for 32 Hz … 16 kHz, modeled on common music-player curves.
enum EQPreset: String, CaseIterable, Identifiable {
    case flat, bassBoost, bassReducer, trebleBoost, trebleReducer, vocal, spokenWord, loudness, acoustic, classical, electronic, hipHop, jazz, pop, rock, smallSpeakers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: "Flat"
        case .bassBoost: "Bass Boost"
        case .bassReducer: "Bass Reducer"
        case .trebleBoost: "Treble Boost"
        case .trebleReducer: "Treble Reducer"
        case .vocal: "Vocal Booster"
        case .spokenWord: "Spoken Word"
        case .loudness: "Loudness"
        case .acoustic: "Acoustic"
        case .classical: "Classical"
        case .electronic: "Electronic"
        case .hipHop: "Hip-Hop"
        case .jazz: "Jazz"
        case .pop: "Pop"
        case .rock: "Rock"
        case .smallSpeakers: "Small Speakers"
        }
    }
    var bands: [Float] {
        switch self {
        case .flat: AppMix.flatEQ
        case .bassBoost: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0]
        case .bassReducer: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]
        case .trebleReducer: [0, 0, 0, 0, 0, -1, -2.5, -4, -5, -6]
        case .vocal: [-2, -3, -3, 1, 4, 4, 3.5, 1.5, 0, -1.5]
        case .spokenWord: [-4, -1, 0, 1, 3.5, 4.5, 4.5, 4, 2.5, 0]
        case .loudness: [5, 4, 1, 0, -1, 0, 0, 1, 4, 3]
        case .acoustic: [4.5, 4.5, 3.5, 1, 1.5, 1.5, 3, 3.5, 3, 1.5]
        case .classical: [4.5, 3.5, 3, 2.5, -1.5, -1.5, 0, 2, 3, 3.5]
        case .electronic: [4, 3.5, 1, 0, -2, 2, 1, 1, 4, 5]
        case .hipHop: [5, 4, 1.5, 3, -1, -1, 1.5, -0.5, 2, 3]
        case .jazz: [4, 3, 1.5, 2, -1.5, -1.5, 0, 1.5, 3, 3.5]
        case .pop: [-1.5, -1, 0, 2, 4, 4, 2, 0, -1, -1.5]
        case .rock: [5, 4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4.5]
        case .smallSpeakers: [-6, -3, 2, 3, 2, 0, 0, 1, 2, 1]
        }
    }
    static func matching(_ bands: [Float]) -> EQPreset? { allCases.first { $0.bands == bands } }
}

/// Command-line diagnostics must tolerate an option with no following value.
enum LaunchArguments {
    static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("--") else { return nil }
        return arguments[index + 1]
    }
}

enum AppInfo {
    static let support = URL(string: "https://ko-fi.com/hiteshgupta")!
    /// Privacy & Security → Screen & System Audio Recording, which includes "System Audio Recording Only".
    static let audioAccessSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var website: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "DeveloperWebsite") as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
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
