import AppKit
import CoreAudio
import AudioDSP

@available(macOS 14.2, *)
final class ProcessMixer {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var state: OpaquePointer?
    let processIDs: [AudioObjectID]
    let outputUID: String
    var peak: Float { state.map(SWMixerPeak) ?? 0 }
    var formatFailed: Bool { state.map(SWMixerFormatFailed) ?? false }

    init(application: AudioApplication, output: AudioDevice, mix: AppMix) throws {
        processIDs = application.processIDs; outputUID = output.uid
        do {
            guard let state = SWMixerCreate() else { throw AudioFailure(operation: "Allocate mixer", status: -108) }
            self.state = state; apply(mix)
            let description = CATapDescription(stereoMixdownOfProcesses: processIDs)
            description.name = "SoundSwipe · \(application.name)"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try Hardware.check(AudioHardwareCreateProcessTap(description, &tap), "Enable application mixing; check System Settings → Privacy & Security → Screen & System Audio Recording")
            let tapFormat = Hardware.read(tap, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
            guard Self.isFloatPCM(tapFormat) else { throw AudioFailure(operation: "Unsupported tap format", status: kAudioHardwareUnsupportedOperationError) }
            let dictionary: [String: Any] = [
                kAudioAggregateDeviceNameKey: "SoundSwipe · \(application.name)",
                kAudioAggregateDeviceUIDKey: "app.soundswipe.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid, kAudioSubDeviceInputChannelsKey: 0]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try Hardware.check(AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregate), "Create audio route")
            for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
                let streams = Hardware.list(aggregate, kAudioDevicePropertyStreams, scope: scope)
                guard !streams.isEmpty else { throw AudioFailure(operation: "No streams on audio route", status: kAudioHardwareUnsupportedOperationError) }
                var channels: UInt32 = 0
                for stream in streams {
                    let format = Hardware.read(stream, kAudioStreamPropertyVirtualFormat, default: AudioStreamBasicDescription())
                    guard Self.isFloatPCM(format) else { throw AudioFailure(operation: "This audio route needs a 32-bit float PCM device", status: kAudioHardwareUnsupportedOperationError) }
                    channels += format.mChannelsPerFrame
                }
                guard channels == 2 else { throw AudioFailure(operation: "Application mixing currently requires a stereo device", status: kAudioHardwareUnsupportedOperationError) }
            }
            refreshSampleRate()
            try Hardware.check(AudioDeviceCreateIOProcID(aggregate, SWMixerRender, UnsafeMutableRawPointer(state), &io), "Prepare audio route")
            try Hardware.check(AudioDeviceStart(aggregate, io), "Start audio route")
        } catch { stop(); throw error }
    }
    private static func isFloatPCM(_ f: AudioStreamBasicDescription) -> Bool {
        f.mFormatID == kAudioFormatLinearPCM && f.mBitsPerChannel == 32 && f.mFormatFlags & kAudioFormatFlagIsFloat != 0 && f.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
    }
    func apply(_ mix: AppMix) {
        guard let state else { return }
        SWMixerSetGain(state, mix.effectiveGain)
        SWMixerSetBalance(state, mix.balance)
        mix.activeEQ.withUnsafeBufferPointer { SWMixerSetEQ(state, $0.baseAddress, Int32($0.count)) }
    }
    /// EQ coefficients depend on the device rate, which can change while routing (for example Bluetooth profile switches).
    func refreshSampleRate() {
        guard let state, aggregate != 0 else { return }
        SWMixerSetSampleRate(state, Hardware.read(aggregate, kAudioDevicePropertyNominalSampleRate, default: Float64(48000)))
    }
    func stop() {
        if let io, aggregate != 0 { AudioDeviceStop(aggregate, io); AudioDeviceDestroyIOProcID(aggregate, io) }
        io = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if let state { SWMixerDestroy(state) }; state = nil
    }
    deinit { stop() }
}
