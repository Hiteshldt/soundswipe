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

    static func discover() -> [AudioApplication] {
        struct Group { var name: String; var icon: NSImage?; var processes: [AudioObjectID] = []; var playing = false; var recording = false }
        var groups: [String: Group] = [:]
        let ownPID = getpid()
        for process in Hardware.list(Hardware.system, kAudioHardwarePropertyProcessObjectList) {
            let pid = Hardware.read(process, kAudioProcessPropertyPID, default: pid_t(0))
            guard pid > 0, pid != ownPID else { continue }
            let bundle = Hardware.string(process, kAudioProcessPropertyBundleID)
            let key: String, name: String, icon: NSImage?
            if let owner = owningApplication(of: pid) {
                key = owner.bundleIdentifier ?? "pid:\(owner.processIdentifier)"
                name = owner.localizedName ?? key; icon = owner.icon
            } else {
                // Background services keep their own identity; ownership is never guessed.
                let running = NSRunningApplication(processIdentifier: pid)
                key = bundle.isEmpty ? "pid:\(pid)" : bundle
                name = running?.localizedName ?? (bundle.isEmpty ? "Process \(pid)" : bundle.split(separator: ".").last.map(String.init) ?? bundle)
                icon = running?.icon
            }
            var group = groups[key] ?? Group(name: clean(name), icon: icon)
            group.processes.append(process)
            group.playing = group.playing || Hardware.read(process, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
            group.recording = group.recording || Hardware.read(process, kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0
            groups[key] = group
        }
        return groups.map { AudioApplication(id: $0.key, name: $0.value.name, processIDs: $0.value.processes.sorted(), icon: $0.value.icon, isPlaying: $0.value.playing, isRecording: $0.value.recording) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

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
    /// Removes invisible direction marks and other format characters some apps put in their names.
    static func clean(_ name: String) -> String {
        let scalars = name.unicodeScalars.filter { $0.properties.generalCategory != .format && !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Unknown app" : result
    }
}
