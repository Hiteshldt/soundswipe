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
    /// Apps shown in the panel: active now, active in the last `recentWindow`, or currently routed.
    @Published private(set) var applications: [AudioApplication] = []
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var outputID: AudioObjectID = 0
    @Published private(set) var inputID: AudioObjectID = 0
    @Published private(set) var outputVolume: Float?
    @Published private(set) var inputVolume: Float?
    @Published private(set) var outputMuted = false
    @Published private(set) var inputMuted = false
    /// Volume of every output device that exposes one (fixed-volume devices are absent).
    @Published private(set) var deviceVolumes: [AudioObjectID: Float] = [:]
    @Published private(set) var mutedDevices: Set<AudioObjectID> = []
    @Published private(set) var mixingEnabled = false
    @Published private(set) var mixingNeedsRetry = false
    /// The last failure was macOS denying audio capture, so the banner offers Privacy & Security.
    @Published private(set) var mixingNeedsAccess = false
    @Published private(set) var audioAccess = AudioAccess.current
    @Published private(set) var controlledApps: Set<String> = []
    @Published var error: String?
    let preferences: Preferences
    let levels = LevelMeters()
    static let recentWindow: TimeInterval = 30
    private var allApplications: [AudioApplication] = []
    private var lastActive: [String: Date] = [:]
    private var observations: [AudioObservation] = []
    private var deviceObservations: [AudioObservation] = []
    private var routeFormats: [AudioObjectID: AudioRouteFormat] = [:]
    private var mixers: [String: ProcessMixer] = [:]
    private var healthTimer: Timer?
    private var routeRetry: Task<Void, Never>?
    private var routeRetried = false
    private var accessRequestPending = false
    private var panelTimer: Timer?
    private var meterTimer: Timer?
    private var panelVisible = false
    private var resumeAfterWake = false
    private var volumesBeforeMute = MuteRestoreLevels()
    private var workspaceObservers: [NSObjectProtocol] = []
    var outputs: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputs: [AudioDevice] { devices.filter(\.hasInput) }
    var microphoneUsers: [AudioApplication] { allApplications.filter(\.isRecording) }
    var outputName: String { devices.first { $0.id == outputID }?.name ?? "No output device" }
    var inputName: String { devices.first { $0.id == inputID }?.name ?? "No input device" }

    init(preferences: Preferences) {
        self.preferences = preferences
        // Settings for a specific process or extra app copy cannot apply after a relaunch.
        let stale = preferences.mixes.keys.filter(AudioApplication.isSessionKey)
        if !stale.isEmpty { stale.forEach { preferences.mixes.removeValue(forKey: $0) } }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            observations.append(AudioObservation(Hardware.system, selector: selector) { [weak self] in
                Task { @MainActor in self?.refresh() }
            })
        }
        observations.append(AudioObservation(Hardware.system, selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
            Task { @MainActor in self?.refreshApplications() }
        })
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

    // MARK: Devices

    func refresh() {
        let oldOutput = outputID, oldInput = inputID
        let newDevices = AudioDevice.discover()
        let deviceChanged = devices != newDevices
        devices = newDevices
        outputID = Hardware.read(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
        inputID = Hardware.read(Hardware.system, kAudioHardwarePropertyDefaultInputDevice, default: AudioObjectID(0))
        let newFormats = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, AudioRouteFormat.read($0.id)) })
        let formatChanged = routeFormats != newFormats
        routeFormats = newFormats
        if formatChanged || oldOutput != outputID || oldInput != inputID || deviceChanged || deviceObservations.isEmpty {
            deviceObservations.removeAll()
            // Every output is observed so the device list stays live; only the default input is shown.
            let watched = outputs.map { ($0.id, kAudioObjectPropertyScopeOutput) } + (inputID != 0 ? [(inputID, kAudioObjectPropertyScopeInput)] : [])
            for (id, scope) in watched {
                // Revalidate byte layout and channel count after a Bluetooth
                // profile, stream configuration, or sample-rate change.
                if scope == kAudioObjectPropertyScopeOutput {
                    for selector in [kAudioDevicePropertyStreams, kAudioDevicePropertyStreamConfiguration] {
                        deviceObservations.append(AudioObservation(id, selector: selector, scope: scope) { [weak self] in
                            Task { @MainActor in self?.refresh() }
                        })
                    }
                    deviceObservations.append(AudioObservation(id, selector: kAudioDevicePropertyNominalSampleRate) { [weak self] in
                        Task { @MainActor in self?.refresh() }
                    })
                    for stream in Hardware.list(id, kAudioDevicePropertyStreams, scope: scope) {
                        deviceObservations.append(AudioObservation(stream, selector: kAudioStreamPropertyVirtualFormat) { [weak self] in
                            Task { @MainActor in self?.refresh() }
                        })
                    }
                }
                for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    for element: UInt32 in [0, 1, 2] {
                        deviceObservations.append(AudioObservation(id, selector: selector, scope: scope, element: element) { [weak self] in Task { @MainActor in self?.refreshVolumes() } })
                    }
                }
            }
            // Rebuild routes after hardware changes, even if the UID stayed the same.
            mixers.removeAll()
        }
        refreshVolumes()
        refreshApplications()
    }
    func refreshVolumes() {
        var volumes: [AudioObjectID: Float] = [:], muted: Set<AudioObjectID> = []
        for device in outputs {
            let volume = Hardware.volume(device.id, scope: kAudioObjectPropertyScopeOutput)
            if let volume { volumes[device.id] = volume }
            if Hardware.read(device.id, kAudioDevicePropertyMute, default: UInt32(0), scope: kAudioObjectPropertyScopeOutput) != 0 || volume == 0 { muted.insert(device.id) }
        }
        if volumes != deviceVolumes { deviceVolumes = volumes }
        if muted != mutedDevices { mutedDevices = muted }
        outputVolume = Hardware.volume(outputID, scope: kAudioObjectPropertyScopeOutput)
        inputVolume = Hardware.volume(inputID, scope: kAudioObjectPropertyScopeInput)
        outputMuted = Hardware.read(outputID, kAudioDevicePropertyMute, default: UInt32(0), scope: kAudioObjectPropertyScopeOutput) != 0 || outputVolume == 0
        inputMuted = Hardware.read(inputID, kAudioDevicePropertyMute, default: UInt32(0), scope: kAudioObjectPropertyScopeInput) != 0 || inputVolume == 0
    }
    func selectOutput(_ id: AudioObjectID) { perform { try Hardware.write(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, id) }; refresh() }
    func selectInput(_ id: AudioObjectID) { perform { try Hardware.write(Hardware.system, kAudioHardwarePropertyDefaultInputDevice, id) }; refresh() }
    func setOutputVolume(_ value: Float) { setVolume(value, device: outputID, scope: kAudioObjectPropertyScopeOutput) }
    func setInputVolume(_ value: Float) { setVolume(value, device: inputID, scope: kAudioObjectPropertyScopeInput) }
    func setVolume(_ value: Float, output device: AudioObjectID) { setVolume(value, device: device, scope: kAudioObjectPropertyScopeOutput) }
    private func setVolume(_ value: Float, device: AudioObjectID, scope: AudioObjectPropertyScope) {
        perform {
            try Hardware.setVolume(device, scope: scope, value: value)
            if value > 0 && Hardware.writable(device, kAudioDevicePropertyMute, scope: scope) {
                try Hardware.write(device, kAudioDevicePropertyMute, UInt32(0), scope: scope)
            }
        }
        refreshVolumes()
    }
    func toggleMute() { toggleMute(output: outputID) }
    func toggleMute(output device: AudioObjectID) {
        toggleMute(device: device, scope: kAudioObjectPropertyScopeOutput, muted: mutedDevices.contains(device), volume: deviceVolumes[device],
                   unsupported: "This output has fixed volume. Use its hardware controls.")
    }
    func toggleInputMute() {
        toggleMute(device: inputID, scope: kAudioObjectPropertyScopeInput, muted: inputMuted, volume: inputVolume,
                   unsupported: "This microphone cannot be muted from macOS. Use its hardware controls.")
    }
    /// Prefers the device's mute switch; falls back to volume 0 and restores the previous level.
    private func toggleMute(device: AudioObjectID, scope: AudioObjectPropertyScope, muted: Bool, volume: Float?, unsupported: String) {
        let saved = volumesBeforeMute.volume(device: device, scope: scope)
        if !muted { volumesBeforeMute.remember(volume, device: device, scope: scope) }
        if Hardware.writable(device, kAudioDevicePropertyMute, scope: scope) {
            perform { try Hardware.write(device, kAudioDevicePropertyMute, UInt32(muted ? 0 : 1), scope: scope) }
            if muted && volume == 0 { setVolume(saved, device: device, scope: scope) }
        } else if let volume {
            if volume > 0 { setVolume(0, device: device, scope: scope) } else { setVolume(saved, device: device, scope: scope) }
        } else { error = unsupported }
        refreshVolumes()
    }
    func nextOutput() {
        guard !outputs.isEmpty else { return }
        let index = outputs.firstIndex { $0.id == outputID } ?? -1
        selectOutput(outputs[(index + 1) % outputs.count].id)
    }

    // MARK: Applications

    /// Core Audio notifies when processes appear or exit, but not when they start or stop playing,
    /// so activity is re-read on a slow timer only while the panel is visible.
    func refreshApplications() {
        let discovered = AudioApplication.discover()
        let now = Date()
        for app in discovered where app.isActive { lastActive[app.id] = now }
        let present = Set(discovered.map(\.id))
        lastActive = lastActive.filter { present.contains($0.key) && now.timeIntervalSince($0.value) < Self.recentWindow }
        allApplications = discovered
        reconcileMixers()
        let visible = discovered.filter { lastActive[$0.id] != nil || mixers[$0.id] != nil }
        if visible != applications { applications = visible }
    }

    func setMixing(_ enabled: Bool) {
        if enabled {
            // Check access before any tap mutes an app, so a missing grant cannot leave it silent.
            refreshAccess()
            switch audioAccess {
            case .denied: showAccessError(); return
            case .notDetermined: requestAccess(); return
            case .granted, .unavailable: break
            }
            mixingNeedsRetry = false; mixingNeedsAccess = false; routeRetried = false; error = nil
        }
        else { routeRetry?.cancel(); routeRetry = nil }
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
                            self.mixingNeedsRetry = true
                            self.setMixing(false)
                        } else {
                            self.mixers.values.forEach { $0.refreshSampleRate() }
                        }
                    }
                }
                healthTimer?.tolerance = 0.3
            }
        } else { healthTimer?.invalidate(); healthTimer = nil; mixers.removeAll(); controlledApps = [] }
        updateTimers()
        refreshApplications()
    }
    func mix(for app: AudioApplication) -> AppMix { preferences.mixes[app.id] ?? AppMix() }
    func updateMix(_ app: AudioApplication, _ update: (inout AppMix) -> Void) {
        var mix = mix(for: app); update(&mix)
        preferences.mixes[app.id] = mix == AppMix() ? nil : mix
        // Adjusting an app is an explicit request to control it; macOS asks for audio access the first time.
        // A failed tap must not retry for every mouse movement during a drag.
        // The user can grant access, then explicitly retry from the banner or Mix switch.
        if !mixingEnabled && mix.needsMixing && !mixingNeedsRetry { setMixing(true) } else { reconcileMixers() }
        objectWillChange.send()
    }
    func resetMixes() { preferences.mixes = [:]; reconcileMixers(); objectWillChange.send() }
    private func reconcileMixers() {
        guard mixingEnabled else { return }
        let present = Set(allApplications.map(\.id))
        for key in Array(mixers.keys) where !present.contains(key) { mixers.removeValue(forKey: key) }
        for app in allApplications {
            let mix = mix(for: app)
            // Keep an already-authorized route at unity gain. Dragging through
            // 100% must not destroy/recreate its tap and ask for capture again.
            // Turning Mix off, app exit, or shutdown still releases the route.
            guard mix.needsMixing || mixers[app.id] != nil else { continue }
            // An unplugged saved route falls back to the system output.
            guard let output = outputs.first(where: { $0.uid == mix.outputUID }) ?? outputs.first(where: { $0.id == outputID }) else {
                mixers.removeValue(forKey: app.id); continue
            }
            if let mixer = mixers[app.id], mixer.processIDs == app.processIDs, mixer.outputUID == output.uid { mixer.apply(mix); continue }
            mixers.removeValue(forKey: app.id)
            do { mixers[app.id] = try ProcessMixer(application: app, output: output, mix: mix) }
            catch {
                let needsAccess = (error as? AudioFailure)?.needsAccess == true
                // A Bluetooth profile switch (for example when a call takes the headset mic) briefly
                // republishes the device. The app plays unprocessed meanwhile; try once more first.
                // Bursts of change notifications during the switch keep postponing that one retry.
                if !needsAccess && (!routeRetried || routeRetry != nil) { scheduleRouteRetry(); continue }
                self.error = error.localizedDescription + (needsAccess
                    ? " Mixing has been stopped; original audio is restored. Allow SoundSwipe, then choose Retry."
                    : " Mixing has been stopped; original audio is restored. Check your output device, then choose Retry.")
                mixingNeedsRetry = true
                setMixing(false)
                mixingNeedsAccess = needsAccess
                return
            }
        }
        let controlled = Set(mixers.keys)
        if controlled != controlledApps { controlledApps = controlled }
    }

    func refreshAccess() {
        let current = AudioAccess.current
        if current != audioAccess { audioAccess = current }
        if current == .granted && mixingNeedsAccess && !mixingEnabled { mixingNeedsAccess = false; error = nil }
    }
    /// Shows the macOS prompt once; a denied or dismissed prompt leaves the Settings link in the panel.
    func requestAccess() {
        guard !accessRequestPending else { return }
        accessRequestPending = true
        AudioAccess.request { [weak self] granted in
            guard let self else { return }
            self.accessRequestPending = false
            self.refreshAccess()
            if granted || self.audioAccess == .granted { self.setMixing(true) } else { self.showAccessError() }
        }
    }
    private func showAccessError() {
        if mixingEnabled { setMixing(false) }
        error = "SoundSwipe needs System Audio Recording access to control individual apps. Turn on SoundSwipe under System Audio Recording Only, then choose Retry."
        mixingNeedsRetry = true; mixingNeedsAccess = true
    }

    private func scheduleRouteRetry() {
        routeRetried = true
        routeRetry?.cancel()
        routeRetry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            self.routeRetry = nil
            self.reconcileMixers()
            // Still mixing means the retry worked; a later device change gets its own retry.
            if self.mixingEnabled && self.routeRetry == nil { self.routeRetried = false }
        }
    }

    // MARK: Panel-only timers

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { refreshAccess(); refresh() }
        updateTimers()
    }
    private func updateTimers() {
        if panelVisible, panelTimer == nil {
            panelTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshApplications() }
            }
            panelTimer?.tolerance = 0.2
        } else if !panelVisible {
            panelTimer?.invalidate(); panelTimer = nil
        }
        let metering = panelVisible && mixingEnabled
        guard metering != (meterTimer != nil) else { return }
        meterTimer?.invalidate(); meterTimer = nil
        guard metering else { levels.values = [:]; return }
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

    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
    func shutdown() {
        panelVisible = false; setMixing(false)
        observations.removeAll(); deviceObservations.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }
}
