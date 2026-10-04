import AppKit
import CoreAudio

/// One user-facing app, grouping every Core Audio process it owns (for example a browser and its helpers).
struct AudioApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let processIDs: [AudioObjectID]
    let icon: NSImage?
    /// Currently sending audio to an output device.
    let isPlaying: Bool
    /// Currently receiving audio from an input device (microphone in use).
    let isRecording: Bool
    var isActive: Bool { isPlaying || isRecording }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.processIDs == rhs.processIDs && lhs.isPlaying == rhs.isPlaying && lhs.isRecording == rhs.isRecording
    }

    /// One Core Audio process, resolved to the app instance that owns it.
    struct ProcessEntry {
        let process: AudioObjectID
        /// Bundle ID of the owning app (or the process itself), used as the stable identity.
        let bundleKey: String
        /// PID of the owning app instance; separates two running copies of the same app.
        let instance: pid_t
        let name: String
        var icon: NSImage? = nil
        var playing = false
        var recording = false
    }

    static func discover() -> [AudioApplication] {
        let ownPID = getpid()
        let entries: [ProcessEntry] = Hardware.list(Hardware.system, kAudioHardwarePropertyProcessObjectList).compactMap { process in
            let pid = Hardware.read(process, kAudioProcessPropertyPID, default: pid_t(0))
            guard pid > 0, pid != ownPID else { return nil }
            let bundle = Hardware.string(process, kAudioProcessPropertyBundleID)
            let playing = Hardware.read(process, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
            let recording = Hardware.read(process, kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0
            if let owner = owningApplication(of: pid) {
                let key = owner.bundleIdentifier ?? "pid:\(owner.processIdentifier)"
                return ProcessEntry(process: process, bundleKey: key, instance: owner.processIdentifier, name: clean(owner.localizedName ?? key),
                                    icon: owner.icon, playing: playing, recording: recording)
            }
            // Background services (for example WebKit media for Safari) keep their own identity; ownership is never guessed.
            let running = NSRunningApplication(processIdentifier: pid)
            let name = running?.localizedName ?? (bundle.isEmpty ? executableName(of: pid) ?? "Process \(pid)" : bundle.split(separator: ".").last.map(String.init) ?? bundle)
            // Apple background services such as Siri's wake-word listener hold the microphone constantly;
            // like the system's own privacy indicator, their input is not reported as microphone use.
            let systemListener = bundle.hasPrefix("com.apple.") && running?.activationPolicy != .regular
            return ProcessEntry(process: process, bundleKey: bundle.isEmpty ? "pid:\(pid)" : bundle, instance: pid, name: clean(name),
                                icon: running?.icon, playing: playing, recording: recording && !systemListener)
        }
        return group(entries)
    }

    /// Groups processes into one row per app instance.
    /// - One instance of an app keeps its bundle ID as its key, so saved settings survive relaunches.
    /// - Instances with different names (for example WebKit media processes serving different apps) are keyed by name.
    /// - Further copies with the same name are numbered and get a session-only key containing `#`.
    static func group(_ entries: [ProcessEntry]) -> [AudioApplication] {
        var apps: [AudioApplication] = []
        // Another running copy owns the mixer's tap input/output, not a user's
        // microphone session. Never offer to tap our own routed audio again.
        let external = entries.filter { $0.bundleKey != "app.soundswipe.SoundSwipe" }
        for (bundleKey, bundleEntries) in Dictionary(grouping: external, by: \.bundleKey) {
            let byName = Dictionary(grouping: bundleEntries, by: \.name)
            for (name, named) in byName {
                let baseKey = byName.count > 1 ? "\(bundleKey)|\(name)" : bundleKey
                let instances = Dictionary(grouping: named, by: \.instance).sorted { $0.key < $1.key }
                for (index, (instance, processes)) in instances.enumerated() {
                    apps.append(AudioApplication(
                        id: index == 0 ? baseKey : "\(baseKey)#\(instance)",
                        name: index == 0 ? name : "\(name) (\(index + 1))",
                        processIDs: processes.map(\.process).sorted(),
                        icon: processes.lazy.compactMap(\.icon).first,
                        isPlaying: processes.contains(where: \.playing),
                        isRecording: processes.contains(where: \.recording)))
                }
            }
        }
        // Separate processes that report the same name (for example two command-line players) get numbered too.
        for (_, indices) in Dictionary(grouping: apps.indices, by: { apps[$0].name }) where indices.count > 1 {
            for (number, index) in indices.sorted(by: { apps[$0].processIDs.first ?? 0 < apps[$1].processIDs.first ?? 0 }).enumerated().dropFirst() {
                let app = apps[index]
                apps[index] = AudioApplication(id: app.id, name: "\(app.name) (\(number + 1))", processIDs: app.processIDs, icon: app.icon,
                                               isPlaying: app.isPlaying, isRecording: app.isRecording)
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Keys that identify a single process or app instance and are meaningless after relaunch.
    static func isSessionKey(_ key: String) -> Bool { key.hasPrefix("pid:") || key.contains("#") }

    /// The top-most regular (Dock) app in the verified parent-process chain, so helper processes group under their app.
    private static func owningApplication(of pid: pid_t) -> NSRunningApplication? {
        var current = pid, owner: NSRunningApplication?
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { owner = app }
            let parent = parentPID(of: current)
            guard parent > 1, parent != current else { break }
            current = parent
        }
        return owner
    }
    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }
    private static func executableName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
    /// Removes invisible direction marks and other format characters some apps put in their names.
    static func clean(_ name: String) -> String {
        let scalars = name.unicodeScalars.filter { $0.properties.generalCategory != .format && !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Unknown app" : result
    }
}
