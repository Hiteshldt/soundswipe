import AppKit
import CoreAudio
import AudioDSP

struct AudioApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let processIDs: [AudioObjectID]
    let icon: NSImage?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.processIDs == rhs.processIDs }
    static func discover() -> [AudioApplication] {
        var groups: [String: (String, [AudioObjectID], NSImage?)] = [:]
        for process in Hardware.list(Hardware.system, kAudioHardwarePropertyProcessObjectList) {
            let pid = Hardware.read(process, kAudioProcessPropertyPID, default: pid_t(0))
            guard pid != getpid(), pid > 0 else { continue }
            let bundle = Hardware.string(process, kAudioProcessPropertyBundleID)
            let running = NSRunningApplication(processIdentifier: pid)
            // Keep helper processes visible under their reported identity instead of
            // guessing ownership and accidentally taking control of unrelated audio.
            let key = bundle.isEmpty ? "pid:\(pid)" : bundle
            let name = running?.localizedName ?? (bundle.isEmpty ? "Audio process \(pid)" : bundle)
            if groups[key] != nil { groups[key]!.1.append(process) }
            else { groups[key] = (name, [process], running?.icon) }
        }
        return groups.map { AudioApplication(id: $0.key, name: $0.value.0, processIDs: $0.value.1.sorted(), icon: $0.value.2) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

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

    init(application: AudioApplication, output: AudioDevice, gain: Float) throws {
        processIDs = application.processIDs; outputUID = output.uid
        do {
            guard let state = SWMixerCreate() else { throw AudioFailure(operation: "Allocate mixer", status: -108) }
            self.state = state; SWMixerSetGain(state, gain)
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
            try Hardware.check(AudioDeviceCreateIOProcID(aggregate, SWMixerRender, UnsafeMutableRawPointer(state), &io), "Prepare audio route")
            try Hardware.check(AudioDeviceStart(aggregate, io), "Start audio route")
        } catch { stop(); throw error }
    }
    private static func isFloatPCM(_ f: AudioStreamBasicDescription) -> Bool {
        f.mFormatID == kAudioFormatLinearPCM && f.mBitsPerChannel == 32 && f.mFormatFlags & kAudioFormatFlagIsFloat != 0 && f.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
    }
    func setGain(_ gain: Float) { if let state { SWMixerSetGain(state, gain) } }
    func stop() {
        if let io, aggregate != 0 { AudioDeviceStop(aggregate, io); AudioDeviceDestroyIOProcID(aggregate, io) }
        io = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if let state { SWMixerDestroy(state) }; state = nil
    }
    deinit { stop() }
}
