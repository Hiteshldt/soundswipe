import CoreAudio
import Foundation

struct AudioFailure: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "\(operation) failed (Core Audio \(status))." }
}

/// Input and output on a duplex device have independent mute restore levels.
struct MuteRestoreLevels {
    private struct Key: Hashable {
        let device: AudioObjectID
        let scope: AudioObjectPropertyScope
    }
    private var levels: [Key: Float] = [:]
    mutating func remember(_ volume: Float?, device: AudioObjectID, scope: AudioObjectPropertyScope) {
        guard let volume, volume.isFinite, volume > 0 else { return }
        levels[Key(device: device, scope: scope)] = min(1, volume)
    }
    func volume(device: AudioObjectID, scope: AudioObjectPropertyScope) -> Float {
        levels[Key(device: device, scope: scope)] ?? 0.5
    }
}

/// Compare actual route formats, rather than rebuilding on duplicate notifications.
struct AudioRouteFormat: Equatable {
    let sampleRate: Double
    let streams: [Stream]
    struct Stream: Equatable {
        let id: AudioObjectID
        let sampleRate: Double
        let formatID: UInt32
        let flags: UInt32
        let bytesPerPacket: UInt32
        let framesPerPacket: UInt32
        let bytesPerFrame: UInt32
        let channels: UInt32
        let bitsPerChannel: UInt32
        init(id: AudioObjectID, format: AudioStreamBasicDescription) {
            self.id = id; sampleRate = format.mSampleRate; formatID = format.mFormatID
            flags = format.mFormatFlags; bytesPerPacket = format.mBytesPerPacket
            framesPerPacket = format.mFramesPerPacket; bytesPerFrame = format.mBytesPerFrame
            channels = format.mChannelsPerFrame; bitsPerChannel = format.mBitsPerChannel
        }
    }
    static func read(_ device: AudioObjectID) -> Self {
        Self(sampleRate: Hardware.read(device, kAudioDevicePropertyNominalSampleRate, default: Float64(0)),
             streams: Hardware.list(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).sorted().map {
                 Stream(id: $0, format: Hardware.read($0, kAudioStreamPropertyVirtualFormat, default: AudioStreamBasicDescription()))
             })
    }
}

enum Hardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }
    static func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw AudioFailure(operation: operation, status: status) }
    }
    static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) -> T {
        var result = value; var size = UInt32(MemoryLayout<T>.size)
        var a = address(selector, scope: scope, element: element)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return status == noErr ? result : value
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var result: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
        var a = address(selector)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return status == noErr ? result as String : ""
    }
    static func list(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = address(selector, scope: scope); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? Array(ids.prefix(Int(size) / 4)) : []
    }
    static func write<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) throws {
        var a = address(selector, scope: scope, element: element); var v = value
        try check(withUnsafePointer(to: &v) { AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0) }, "Change audio setting")
    }
    static func writable(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: UInt32 = 0) -> Bool {
        var a = address(selector, scope: scope, element: element); var yes: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &a, &yes) == noErr && yes.boolValue
    }
    static func volumeElements(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> [UInt32] {
        if writable(id, kAudioDevicePropertyVolumeScalar, scope: scope) { return [0] }
        return [1, 2].filter { writable(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
    }
    static func volume(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Float? {
        let elements = volumeElements(id, scope: scope)
        guard !elements.isEmpty else { return nil }
        return elements.map { read(id, kAudioDevicePropertyVolumeScalar, default: Float(0), scope: scope, element: $0) }.reduce(0, +) / Float(elements.count)
    }
    static func setVolume(_ id: AudioObjectID, scope: AudioObjectPropertyScope, value: Float) throws {
        let elements = volumeElements(id, scope: scope)
        guard !elements.isEmpty else { throw AudioFailure(operation: "This device has fixed volume", status: kAudioHardwareUnsupportedOperationError) }
        for element in elements { try write(id, kAudioDevicePropertyVolumeScalar, min(1, max(0, value)), scope: scope, element: element) }
    }
}

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let hasOutput: Bool
    let hasInput: Bool
    var transport: UInt32 = 0
    static func discover() -> [AudioDevice] {
        Hardware.list(Hardware.system, kAudioHardwarePropertyDevices).compactMap { id in
            let uid = Hardware.string(id, kAudioDevicePropertyDeviceUID)
            guard !uid.hasPrefix("app.soundswipe."), !uid.isEmpty else { return nil }
            return AudioDevice(id: id, uid: uid, name: AudioApplication.clean(Hardware.string(id, kAudioObjectPropertyName)),
                               hasOutput: !Hardware.list(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).isEmpty,
                               hasInput: !Hardware.list(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).isEmpty,
                               transport: Hardware.read(id, kAudioDevicePropertyTransportType, default: UInt32(0)))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// SF Symbol for the device, from its name (for AirPods and similar) and connection type.
    var symbol: String { Self.symbol(name: name, transport: transport, output: hasOutput) }
    static func symbol(name: String, transport: UInt32, output: Bool) -> String {
        let lower = name.lowercased()
        let byName: [(String, String)] = [("airpods max", "airpodsmax"), ("airpods pro", "airpods.pro"), ("airpods", "airpods"),
                                          ("beats", "beats.headphones"), ("headphone", "headphones"), ("headset", "headphones"),
                                          ("homepod", "homepod.fill"), ("display", "display"), ("monitor", "display")]
        if let match = byName.first(where: { lower.contains($0.0) }) { return match.1 }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return output ? "laptopcomputer" : "mic"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return output ? "headphones" : "mic"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire: return output ? "hifispeaker" : "mic"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "waveform"
        default: return output ? "speaker.wave.2" : "mic"
        }
    }
}

final class AudioObservation {
    private let id: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    init(_ id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0, change: @escaping () -> Void) {
        self.id = id; address = Hardware.address(selector, scope: scope, element: element)
        block = { _, _ in change() }
        AudioObjectAddPropertyListenerBlock(id, &address, .main, block)
    }
    deinit { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
}
