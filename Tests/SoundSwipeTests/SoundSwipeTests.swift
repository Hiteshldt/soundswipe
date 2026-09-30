import Testing
import Foundation
import CoreAudio
import AudioDSP
@testable import SoundSwipe

struct SoundSwipeTests {
    @Test func testMixDefaultsAndFiniteGain() {
        var mix = AppMix()
        #expect(!(mix.needsMixing))
        mix.volume = .nan
        #expect(mix.effectiveGain == 1)
        mix.volume = -2
        #expect(mix.effectiveGain == 0)
        mix.muted = true
        #expect(mix.effectiveGain == 0)
    }
    @Test func testSettingsRoundTrip() {
        let name = "SoundSwipeTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Preferences(defaults: defaults)
        first.mixes["example.player"] = AppMix(volume: 0.42, muted: false, outputUID: "headphones")
        first.shortcuts["panel"] = ShortcutBinding(keyCode: 49, modifiers: 256, label: "⌘Space")
        let second = Preferences(defaults: defaults)
        #expect(second.mixes["example.player"] == first.mixes["example.player"])
        #expect(second.shortcuts["panel"] == first.shortcuts["panel"])
    }
    @Test func testDeveloperLinksRejectImpersonationAndUnsafeSchemes() {
        #expect(Preferences.profileURL("https://github.com/hitesh", hosts: ["github.com"]) != nil)
        for url in ["http://github.com/hitesh", "https://github.com.evil.test/hitesh", "https://user@github.com/hitesh", "file:///tmp/file", "https://github.com"] {
            #expect(Preferences.profileURL(url, hosts: ["github.com"]) == nil)
        }
    }
    @Test func testDSPUnityGainAndNonFiniteSamples() {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        let result = render(state, input: [0.25, -0.5, .nan, .infinity])
        #expect(result == [0.25, -0.5, 0, 0])
        #expect(SWMixerPeak(state) == 0.5)
        #expect(SWMixerPeak(state) == 0)
    }
    @Test func testDSPMuteRampsAndStaysBounded() {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        SWMixerSetGain(state, 0)
        let output = render(state, input: Array(repeating: 1, count: 16000))
        #expect(output[0] > 0.9)
        #expect(abs(output.last!) < 0.00001)
        #expect(output.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(output[0] == output[1])
    }
    @Test func testDSPRejectsMonoInputAndClearsOutput() {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        let output = render(state, input: [0.5, 0.5], inputChannels: 1)
        #expect(output == [0, 0])
        #expect(SWMixerFormatFailed(state))
    }
    @Test func testBoostRangeAndMixingNeed() {
        var mix = AppMix()
        mix.volume = 1.5
        #expect(mix.needsMixing)
        #expect(mix.effectiveGain == 1.5)
        mix.volume = 9
        #expect(mix.effectiveGain == AppMix.maxVolume)
        mix.volume = 1.0005
        #expect(!mix.needsMixing)
    }
    @Test func testDSPUnityLeavesLoudSamplesUntouched() {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        #expect(render(state, input: [0.95, -0.99]) == [0.95, -0.99])
    }
    @Test func testDSPBoostIsLimitedAndMonotonic() {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        SWMixerSetGain(state, 50)
        // Let the gain ramp settle at the 2x ceiling, then probe the limiter curve.
        _ = render(state, input: Array(repeating: 0, count: 20000))
        let output = render(state, input: [0.1, -0.1, 0.45, -0.45, 0.8, -0.8, 1, -1])
        #expect(abs(output[0] - 0.2) < 0.001)
        #expect(output.allSatisfy { abs($0) < 1 })
        #expect(output[0] < output[2] && output[2] < output[4] && output[4] < output[6])
        #expect(output[1] == -output[0] && output[7] == -output[6])
        #expect(SWMixerPeak(state) == abs(output[6]))
    }
    @Test func testLegacyMixDecodesWithDefaults() throws {
        let legacy = #"{"volume":0.5,"muted":true,"outputUID":"usb"}"#.data(using: .utf8)!
        let mix = try JSONDecoder().decode(AppMix.self, from: legacy)
        #expect(mix.volume == 0.5 && mix.muted && mix.outputUID == "usb")
        #expect(mix.eq == AppMix.flatEQ && mix.balance == 0 && mix.eqEnabled)
        var eq = AppMix()
        eq.eq = EQPreset.bassBoost.bands
        #expect(eq.needsMixing && eq.eqActive)
        #expect(EQPreset.matching(eq.eq) == .bassBoost)
        eq.eqEnabled = false
        #expect(!eq.eqActive && !eq.needsMixing && eq.activeEQ == AppMix.flatEQ)
        eq.eq = AppMix.flatEQ; eq.eqEnabled = true; eq.balance = -0.5
        #expect(eq.needsMixing && !eq.eqActive)
        // 0.3.x saved bass/mid/treble; they spread across the 10 bands.
        let old = try JSONDecoder().decode(AppMix.self, from: #"{"eq":[6,0,-4]}"#.data(using: .utf8)!)
        #expect(old.eq.count == 10 && old.eq[0] == 6 && old.eq[9] == -4 && old.eq[5] == 0)
        #expect(EQPreset.allCases.allSatisfy { $0.bands.count == 10 && $0.bands.allSatisfy { abs($0) <= AppMix.eqRange } })
    }
    @Test func testGroupingSeparatesInstancesAndSharedServices() {
        typealias E = AudioApplication.ProcessEntry
        let apps = AudioApplication.group([
            // One Chrome: main audio service plus a helper, all tabs and windows share them.
            E(process: 10, bundleKey: "com.google.Chrome", instance: 100, name: "Google Chrome", playing: true),
            E(process: 11, bundleKey: "com.google.Chrome", instance: 100, name: "Google Chrome"),
            // A second Chrome instance (separate profile directory).
            E(process: 12, bundleKey: "com.google.Chrome", instance: 200, name: "Google Chrome", recording: true),
            // WebKit media processes for two different apps share a bundle ID.
            E(process: 20, bundleKey: "com.apple.WebKit.GPU", instance: 300, name: "Safari Graphics and Media", playing: true),
            E(process: 21, bundleKey: "com.apple.WebKit.GPU", instance: 301, name: "Mail Graphics and Media"),
            // Two unrelated command-line processes with the same name.
            E(process: 30, bundleKey: "pid:400", instance: 400, name: "player", playing: true),
            E(process: 31, bundleKey: "pid:401", instance: 401, name: "player", playing: true),
        ])
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        #expect(apps.count == 6)
        #expect(byID["pid:400"]?.name == "player" && byID["pid:401"]?.name == "player (2)")
        #expect(byID["com.google.Chrome"]?.processIDs == [10, 11])
        #expect(byID["com.google.Chrome"]?.isPlaying == true)
        #expect(byID["com.google.Chrome#200"]?.name == "Google Chrome (2)")
        #expect(byID["com.google.Chrome#200"]?.isRecording == true)
        #expect(byID["com.apple.WebKit.GPU|Safari Graphics and Media"]?.processIDs == [20])
        #expect(byID["com.apple.WebKit.GPU|Mail Graphics and Media"]?.processIDs == [21])
        #expect(AudioApplication.isSessionKey("com.google.Chrome#200") && AudioApplication.isSessionKey("pid:42"))
        #expect(!AudioApplication.isSessionKey("com.apple.WebKit.GPU|Safari Graphics and Media"))
    }
    @Test func testNamesDropInvisibleCharacters() {
        #expect(AudioApplication.clean("\u{200E}WhatsApp") == "WhatsApp")
        #expect(AudioApplication.clean("  Music\u{0007} ") == "Music")
        #expect(AudioApplication.clean("\u{200F}") == "Unknown app")
    }
    @Test func testDSPBalanceSilencesOneSide() {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        SWMixerSetBalance(state, -1)
        let output = render(state, input: Array(repeating: 0.5, count: 20000))
        #expect(abs(output[output.count - 2] - 0.5) < 0.0001)
        #expect(abs(output[output.count - 1]) < 0.0001)
    }
    @Test func testDSPEQShapesFrequencies() {
        let flat = sineLevel(frequency: 64, eq: AppMix.flatEQ)
        let bass = sineLevel(frequency: 64, eq: [0, 12, 0, 0, 0, 0, 0, 0, 0, 0])
        let trebleOnBass = sineLevel(frequency: 64, eq: [0, 0, 0, 0, 0, 0, 0, 0, 12, 12])
        let cut = sineLevel(frequency: 8000, eq: [0, 0, 0, 0, 0, 0, 0, 0, -12, 0])
        #expect(abs(flat - 0.25) < 0.001)
        #expect(bass > 0.25 * 3)            // +12 dB is 4x; the limiter keeps it below 1.0.
        #expect(bass < 1)
        #expect(abs(trebleOnBass - 0.25) < 0.02)
        #expect(cut < 0.25 * 0.35)          // -12 dB is 0.25x.
    }
    /// Steady-state peak of a stereo sine through the mixer at 48 kHz.
    private func sineLevel(frequency: Double, eq: [Float]) -> Float {
        let state = SWMixerCreate()!
        defer { SWMixerDestroy(state) }
        SWMixerSetSampleRate(state, 48000)
        eq.withUnsafeBufferPointer { SWMixerSetEQ(state, $0.baseAddress, Int32($0.count)) }
        let frames = 48000
        var input = [Float](repeating: 0, count: frames * 2)
        for f in 0..<frames { let v = Float(0.25 * sin(2 * .pi * frequency * Double(f) / 48000)); input[f * 2] = v; input[f * 2 + 1] = v }
        let output = render(state, input: input)
        return output[(frames)...].map(abs).max() ?? 0
    }
    @Test func testDeviceSymbols() {
        #expect(AudioDevice.symbol(name: "Ronit's AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth, output: true) == "airpods.pro")
        #expect(AudioDevice.symbol(name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn, output: true) == "laptopcomputer")
        #expect(AudioDevice.symbol(name: "External Headphones", transport: kAudioDeviceTransportTypeBuiltIn, output: true) == "headphones")
        #expect(AudioDevice.symbol(name: "LG TV", transport: kAudioDeviceTransportTypeHDMI, output: true) == "tv")
    }
    private func render(_ state: OpaquePointer, input: [Float], inputChannels: UInt32 = 2) -> [Float] {
        var source = input, result = [Float](repeating: 99, count: input.count)
        source.withUnsafeMutableBytes { src in
            result.withUnsafeMutableBytes { dst in
                var inputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: inputChannels, mDataByteSize: UInt32(src.count), mData: src.baseAddress))
                var outputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(dst.count), mData: dst.baseAddress))
                var time = AudioTimeStamp()
                #expect(SWMixerRender(0, &time, &inputList, &time, &outputList, &time, UnsafeMutableRawPointer(state)) == noErr)
            }
        }
        return result
    }
}
