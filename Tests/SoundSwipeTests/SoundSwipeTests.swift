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
