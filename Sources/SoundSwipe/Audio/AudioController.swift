import AppKit
import CoreAudio

/// Separate from AudioController so 20 Hz meter updates redraw only the meters, not the whole panel.
@MainActor
final class LevelMeters: ObservableObject {
    @Published fileprivate(set) var values: [String: Float] = [:]
}

@available(macOS 14.2, *)
@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var applications: [AudioApplication] = []
    @Published private(set) var outputID: AudioObjectID = 0
    @Published private(set) var inputID: AudioObjectID = 0
    @Published private(set) var outputVolume: Float?
    @Published private(set) var inputVolume: Float?
    @Published private(set) var outputMuted = false
    @Published private(set) var mixingEnabled = false
    @Published private(set) var controlledApps: Set<String> = []
    @Published var error: String?
    @Published var search = ""
    let preferences: Preferences
    let levels = LevelMeters()
    private var observations: [AudioObservation] = []
    private var deviceObservations: [AudioObservation] = []
    private var mixers: [String: ProcessMixer] = [:]
    private var healthTimer: Timer?
    private var meterTimer: Timer?
    private var meteringRequested = false
    private var resumeAfterWake = false
    private var volumeBeforeMute: Float = 0.5
    private var workspaceObservers: [NSObjectProtocol] = []
    var outputs: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputs: [AudioDevice] { devices.filter(\.hasInput) }
    var filteredApplications: [AudioApplication] { applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var outputName: String { devices.first { $0.id == outputID }?.name ?? "No output device" }
    var inputName: String { devices.first { $0.id == inputID }?.name ?? "No input device" }

    init(preferences: Preferences) {
        self.preferences = preferences
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyProcessObjectList] {
            observations.append(AudioObservation(Hardware.system, selector: selector) { [weak self] in
                Task { @MainActor in self?.refresh() }
            })
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumeAfterWake = self.mixingEnabled
                self.setMixing(false)
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                // Give Core Audio time to republish devices before rebuilding routes.
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.resumeAfterWake else { return }
                self.resumeAfterWake = false
                self.setMixing(true)
            }
        })
        refresh()
        if preferences.mixAtLaunch { setMixing(true) }
    }
    func refresh() {
        let oldOutput = outputID, oldInput = inputID
        let newDevices = AudioDevice.discover()
        let deviceChanged = devices != newDevices
        devices = newDevices
        outputID = Hardware.read(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
        inputID = Hardware.read(Hardware.system, kAudioHardwarePropertyDefaultInputDevice, default: AudioObjectID(0))
        if oldOutput != outputID || oldInput != inputID || deviceChanged || deviceObservations.isEmpty {
            deviceObservations.removeAll()
            for (id, scope) in [(outputID, kAudioObjectPropertyScopeOutput), (inputID, kAudioObjectPropertyScopeInput)] where id != 0 {
                for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    for element: UInt32 in [0, 1, 2] {
                        deviceObservations.append(AudioObservation(id, selector: selector, scope: scope, element: element) { [weak self] in Task { @MainActor in self?.refreshVolumes() } })
                    }
                }
            }
            // Rebuild routes after hardware changes, even if the UID stayed the same.
            mixers.removeAll()
        }
        applications = AudioApplication.discover()
        refreshVolumes()
        reconcileMixers()
    }
    func refreshVolumes() {
        outputVolume = Hardware.volume(outputID, scope: kAudioObjectPropertyScopeOutput)
        inputVolume = Hardware.volume(inputID, scope: kAudioObjectPropertyScopeInput)
        outputMuted = Hardware.read(outputID, kAudioDevicePropertyMute, default: UInt32(0), scope: kAudioObjectPropertyScopeOutput) != 0 || outputVolume == 0
    }
    func selectOutput(_ id: AudioObjectID) { perform { try Hardware.write(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, id) }; refresh() }
    func selectInput(_ id: AudioObjectID) { perform { try Hardware.write(Hardware.system, kAudioHardwarePropertyDefaultInputDevice, id) }; refresh() }
    func setOutputVolume(_ value: Float) {
        perform {
            try Hardware.setVolume(outputID, scope: kAudioObjectPropertyScopeOutput, value: value)
            if value > 0 && Hardware.writable(outputID, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput) {
                try Hardware.write(outputID, kAudioDevicePropertyMute, UInt32(0), scope: kAudioObjectPropertyScopeOutput)
            }
        }
        refreshVolumes()
    }
    func setInputVolume(_ value: Float) { perform { try Hardware.setVolume(inputID, scope: kAudioObjectPropertyScopeInput, value: value) }; refreshVolumes() }
    func toggleMute() {
        if Hardware.writable(outputID, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput) {
            perform { try Hardware.write(outputID, kAudioDevicePropertyMute, UInt32(outputMuted ? 0 : 1), scope: kAudioObjectPropertyScopeOutput) }
            if outputMuted && outputVolume == 0 { setOutputVolume(volumeBeforeMute) }
        } else if let volume = outputVolume {
            if volume > 0 { volumeBeforeMute = volume; setOutputVolume(0) } else { setOutputVolume(volumeBeforeMute) }
        } else { error = "This output has fixed volume. Use its hardware controls." }
        refreshVolumes()
    }
    func nextOutput() {
        guard !outputs.isEmpty else { return }
        let index = outputs.firstIndex { $0.id == outputID } ?? -1
        selectOutput(outputs[(index + 1) % outputs.count].id)
    }
    func setMixing(_ enabled: Bool) {
        mixingEnabled = enabled
        if enabled {
            reconcileMixers()
            healthTimer?.invalidate()
            if mixingEnabled {
                healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.mixers.values.contains(where: \.formatFailed) {
                            self.error = "The device changed to an unsupported audio format. Mixing was stopped and original audio restored."
                            self.setMixing(false)
                        }
                    }
                }
                healthTimer?.tolerance = 0.3
            }
        } else { healthTimer?.invalidate(); healthTimer = nil; mixers.removeAll(); controlledApps = [] }
        updateMeterTimer()
    }
    /// Meters run only while the panel is visible and mixing is on.
    func setMetering(_ visible: Bool) { meteringRequested = visible; updateMeterTimer() }
    private func updateMeterTimer() {
        let active = meteringRequested && mixingEnabled
        guard active != (meterTimer != nil) else { return }
        meterTimer?.invalidate(); meterTimer = nil
        guard active else { levels.values = [:]; return }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleLevels() }
        }
        meterTimer?.tolerance = 0.01
    }
    private func sampleLevels() {
        var next: [String: Float] = [:]
        for (id, mixer) in mixers {
            // Fast attack, gentle release, and drop to zero once it is visually silent.
            let value = max(mixer.peak, (levels.values[id] ?? 0) * 0.8)
            if value > 0.001 { next[id] = min(1, value) }
        }
        if next != levels.values { levels.values = next }
    }
    func updateMix(_ app: AudioApplication, _ update: (inout AppMix) -> Void) {
        var mix = preferences.mixes[app.id] ?? AppMix(); update(&mix)
        preferences.mixes[app.id] = mix
        reconcileMixers()
        objectWillChange.send()
    }
    func resetMixes() { preferences.mixes = [:]; reconcileMixers(); objectWillChange.send() }
    private func reconcileMixers() {
        guard mixingEnabled else { return }
        let present = Set(applications.map(\.id))
        for key in Array(mixers.keys) where !present.contains(key) { mixers.removeValue(forKey: key) }
        for app in applications {
            let mix = preferences.mixes[app.id] ?? AppMix()
            guard mix.needsMixing else { mixers.removeValue(forKey: app.id); continue }
            // An unplugged saved route falls back to the system output.
            guard let output = outputs.first(where: { $0.uid == mix.outputUID }) ?? outputs.first(where: { $0.id == outputID }) else {
                mixers.removeValue(forKey: app.id); continue
            }
            if let mixer = mixers[app.id], mixer.processIDs == app.processIDs, mixer.outputUID == output.uid { mixer.setGain(mix.effectiveGain); continue }
            mixers.removeValue(forKey: app.id)
            do { mixers[app.id] = try ProcessMixer(application: app, output: output, gain: mix.effectiveGain) }
            catch {
                self.error = error.localizedDescription + " Mixing has been stopped; original audio is restored."
                setMixing(false); return
            }
        }
        controlledApps = Set(mixers.keys)
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
    func shutdown() {
        setMixing(false); observations.removeAll(); deviceObservations.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }
}
