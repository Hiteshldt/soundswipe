import SwiftUI
import CoreAudio

@available(macOS 14.2, *)
struct PanelView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var preferences: Preferences
    var openSettings: () -> Void
    @State private var expanded: Set<String> = Self.snapshotExpanded.map { [$0] } ?? []
    /// Diagnostics only: an app ID to show expanded in `--snapshot` renders.
    nonisolated(unsafe) static var snapshotExpanded: String?
    /// Diagnostics only: renders app controls as they look with mixing on, without creating audio taps.
    nonisolated(unsafe) static var snapshotMixingLook = false
    private var mixingLook: Bool { audio.mixingEnabled || Self.snapshotMixingLook }
    @State private var listHeight: CGFloat = 0
    static let width: CGFloat = 520
    private var accent: Color { Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sectionTitle("OUTPUT DEVICES").padding(.horizontal, 18).padding(.bottom, 6)
            VStack(spacing: 4) { ForEach(audio.outputs) { outputRow($0) } }.padding(.horizontal, 12)
            sectionTitle("INPUT", trailing: AnyView(micInUse)).padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
            inputRow.padding(.horizontal, 12)
            Divider().padding(.horizontal, 18).padding(.top, 14)
            appsHeader.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 6)
            appsList
            if let error = audio.error { errorBanner(error).padding(.horizontal, 12).padding(.bottom, 10) }
            Divider().padding(.horizontal, 18)
            footer
        }
        .frame(width: Self.width)
        .background(.regularMaterial)
    }

    // MARK: Header and sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(accent.gradient, in: RoundedRectangle(cornerRadius: 6))
            Text("SoundSwipe").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 24, height: 24) }
                .buttonStyle(.plain).help("Settings and keyboard shortcuts").accessibilityLabel("Open settings")
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    private func sectionTitle(_ title: String, trailing: AnyView? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
    }

    // MARK: Devices

    private func outputRow(_ device: AudioDevice) -> some View {
        let selected = device.id == audio.outputID
        let muted = audio.mutedDevices.contains(device.id)
        return HStack(spacing: 10) {
            Button { if !selected { audio.selectOutput(device.id) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 15))
                        .foregroundStyle(selected ? accent : Color.secondary.opacity(0.6))
                    DeviceIcon(symbol: device.symbol).frame(width: 20)
                    Text(device.name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(selected ? "\(device.name), current output" : "Use \(device.name)")
            if let volume = audio.deviceVolumes[device.id] {
                iconButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: muted, label: "\(muted ? "Unmute" : "Mute") \(device.name)") {
                    audio.toggleMute(output: device.id)
                }
                Slider(value: Binding(get: { Double(audio.deviceVolumes[device.id] ?? volume) }, set: { audio.setVolume(Float($0), output: device.id) }), in: 0...1)
                    .controlSize(.small).frame(width: 140).accessibilityLabel("\(device.name) volume")
                percentage(muted ? 0 : volume)
            } else {
                Text("Fixed volume").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 140 + 20 + 38 + 20, alignment: .trailing)
                    .help("This device sets its own volume. Use its hardware controls.")
            }
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(selected ? accent.opacity(0.1) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private var micInUse: some View {
        let users = audio.microphoneUsers
        return Group {
            if !users.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("In use by \(users.map(\.name).formatted(.list(type: .and)))").lineLimit(1).truncationMode(.tail)
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).frame(maxWidth: 260, alignment: .trailing)
                    .help(users.map(\.name).joined(separator: ", ")).accessibilityElement(children: .combine)
            }
        }
    }

    private var inputRow: some View {
        let device = audio.inputs.first { $0.id == audio.inputID }
        return HStack(spacing: 10) {
            Menu {
                ForEach(audio.inputs) { input in
                    Button { audio.selectInput(input.id) } label: {
                        if input.id == audio.inputID { Label(input.name, systemImage: "checkmark") } else { Text(input.name) }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    DeviceIcon(symbol: device?.symbol ?? "mic").frame(width: 20)
                    Text(audio.inputName).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }.contentShape(Rectangle())
            }.plainMenu().accessibilityLabel("Input device")
            iconButton(audio.inputMuted ? "mic.slash.fill" : "mic.fill", active: audio.inputMuted, label: audio.inputMuted ? "Unmute microphone" : "Mute microphone") { audio.toggleInputMute() }
            if let volume = audio.inputVolume {
                Slider(value: Binding(get: { Double(audio.inputVolume ?? volume) }, set: { audio.setInputVolume(Float($0)) }), in: 0...1)
                    .controlSize(.small).frame(width: 140).accessibilityLabel("Input level")
                percentage(audio.inputMuted ? 0 : volume)
            } else {
                Text(audio.inputMuted ? "Muted" : "Level set by device").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 140 + 38 + 10, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: Apps

    private var appsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle("APPS")
                Toggle("Mix", isOn: Binding(get: { mixingLook }, set: { audio.setMixing($0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                    .help("Mixing applies per-app volume, EQ, and output. Turn off to restore normal audio instantly.")
            }
            if !mixingLook && !audio.applications.isEmpty {
                Text(audio.mixingNeedsRetry ? "Check audio access, then choose Retry or turn Mix on." : "Adjust any app to start mixing. System-audio access is required.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var appsList: some View {
        if audio.applications.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "speaker.zzz").font(.system(size: 20)).foregroundStyle(.tertiary)
                Text("Nothing is playing").font(.system(size: 12, weight: .medium))
                Text("Apps appear here while they play sound or use the microphone.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 16)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(audio.applications) { app in appRow(app) }
                }.padding(.horizontal, 12).padding(.bottom, 12)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            }
            .frame(height: min(max(listHeight, 48), 420))
            .onPreferenceChange(HeightKey.self) { listHeight = $0 }
        }
    }

    private func appRow(_ app: AudioApplication) -> some View {
        let mix = audio.mix(for: app)
        let isExpanded = expanded.contains(app.id)
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                Group {
                    if let icon = app.icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
                }.frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    activity(app)
                }.frame(width: 100, alignment: .leading).help(app.name)
                HStack(spacing: 7) {
                    iconButton(mix.muted ? "speaker.slash.fill" : "speaker.wave.1.fill", active: mix.muted, label: "\(mix.muted ? "Unmute" : "Mute") \(app.name)") {
                        audio.updateMix(app) { $0.muted.toggle() }
                    }
                    Slider(value: Binding(get: { Double(audio.mix(for: app).volume) }, set: { value in
                        // Snap to 100% so the unchanged position is easy to find on a 0–400% slider.
                        let volume = abs(value - 1) < 0.04 ? 1 : Float(value)
                        audio.updateMix(app) { $0.volume = volume; $0.muted = false }
                    }), in: 0...Double(AppMix.maxVolume))
                        .controlSize(.small).tint(mix.volume > 1.001 ? .orange : accent)
                        // Keep the unity marker aligned when the supported boost range changes.
                        .background {
                            GeometryReader { geometry in
                                Capsule().fill(Color.primary.opacity(0.45)).frame(width: 2, height: 10)
                                    .position(x: 6 + max(0, geometry.size.width - 12) / CGFloat(AppMix.maxVolume), y: geometry.size.height / 2)
                            }
                        }
                        .accessibilityLabel("\(app.name) volume").help("100% is unchanged. Above 100% boosts with a limiter.")
                    percentage(mix.muted ? 0 : mix.volume)
                    SegmentMeter(levels: audio.levels, id: app.id)
                }.opacity(mixingLook ? 1 : 0.6)
                outputMenu(app, mix: mix)
                Button { withAnimation(.easeInOut(duration: 0.15)) { if isExpanded { expanded.remove(app.id) } else { expanded.insert(app.id) } } } label: {
                    Image(systemName: isExpanded ? "xmark" : "slider.vertical.3").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(!isExpanded && (mix.eqActive || abs(mix.balance) > 0.01) ? accent : .secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).help(isExpanded ? "Close equalizer" : "Equalizer and balance")
                    .accessibilityLabel("\(isExpanded ? "Close" : "Open") equalizer for \(app.name)")
            }.padding(.horizontal, 10).frame(height: 44)
            if isExpanded { equalizer(app, mix: mix).padding([.horizontal, .bottom], 10) }
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func activity(_ app: AudioApplication) -> some View {
        HStack(spacing: 5) {
            if app.isPlaying { Label("Playing", systemImage: "speaker.wave.2.fill") }
            if app.isRecording { Label("Mic", systemImage: "mic.fill").foregroundStyle(.orange) }
            if !app.isActive { Text("Idle") }
        }
        .labelStyle(CompactLabel())
        .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
    }

    private func outputMenu(_ app: AudioApplication, mix: AppMix) -> some View {
        let routed = mix.outputUID.flatMap { uid in audio.outputs.first { $0.uid == uid } }
        let system = audio.outputs.first { $0.id == audio.outputID }
        return Menu {
            Button { audio.updateMix(app) { $0.outputUID = nil } } label: {
                let title = "System Output" + (system.map { " (\($0.name))" } ?? "")
                if mix.outputUID == nil { Label(title, systemImage: "checkmark") } else { Text(title) }
            }
            Divider()
            ForEach(audio.outputs) { device in
                Button { audio.updateMix(app) { $0.outputUID = device.uid } } label: {
                    if mix.outputUID == device.uid { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
            Divider()
            Menu("Volume boost") {
                ForEach(1...Int(AppMix.maxVolume), id: \.self) { multiplier in
                    Button("\(multiplier)× (\(multiplier * 100)%)") {
                        audio.updateMix(app) { $0.volume = Float(multiplier); $0.muted = false }
                    }
                }
            }
            Button("Reset \(app.name)") { audio.updateMix(app) { $0 = AppMix() } }
        } label: {
            HStack(spacing: 5) {
                DeviceIcon(symbol: (routed ?? system)?.symbol ?? "speaker.wave.2").frame(width: 14).font(.system(size: 11))
                Text(routed?.name ?? "System").font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(routed == nil ? Color.primary.opacity(0.75) : accent)
            .padding(.horizontal, 8).frame(width: 104, height: 24)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .plainMenu()
        .help(routed.map { "\(app.name) plays on \($0.name)" } ?? "\(app.name) follows the system output")
    }

    private func equalizer(_ app: AudioApplication, mix: AppMix) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { audio.mix(for: app).eqEnabled }, set: { on in audio.updateMix(app) { $0.eqEnabled = on } })) {
                    Text("EQ").font(.system(size: 12, weight: .semibold))
                }.toggleStyle(.switch).controlSize(.small)
                Spacer()
                Text("Preset").font(.system(size: 11)).foregroundStyle(.secondary)
                Menu {
                    ForEach(EQPreset.allCases) { preset in
                        Button { audio.updateMix(app) { $0.eq = preset.bands; $0.eqEnabled = true } } label: {
                            if EQPreset.matching(mix.eq) == preset { Label(preset.title, systemImage: "checkmark") } else { Text(preset.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(EQPreset.matching(mix.eq)?.title ?? "Custom").font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
                    .contentShape(Rectangle())
                }.plainMenu().fixedSize()
            }
            HStack(spacing: 0) {
                ForEach(AppMix.eqFrequencies.indices, id: \.self) { index in
                    VStack(spacing: 5) {
                        VerticalSlider(value: Binding(get: { audio.mix(for: app).eq[index] }, set: { value in
                            audio.updateMix(app) { $0.eq[index] = (value * 2).rounded() / 2; $0.eqEnabled = true }
                        }), range: -AppMix.eqRange...AppMix.eqRange, label: "\(frequencyLabel(AppMix.eqFrequencies[index])) hertz")
                        .frame(height: 104)
                        VStack(spacing: 0) {
                            Text(frequencyLabel(AppMix.eqFrequencies[index])).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            Text("Hz").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }.foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.opacity(mix.eqEnabled ? 1 : 0.45)
            HStack(spacing: 8) {
                Text("Balance").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("L").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                BalanceSlider(value: Binding(get: { audio.mix(for: app).balance }, set: { value in
                    audio.updateMix(app) { $0.balance = abs(value) < 0.05 ? 0 : value }
                })).frame(height: 16)
                Text("R").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Text(balanceText(mix.balance)).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Footer and components

    private var donateLink: some View {
        Link(destination: AppInfo.support) {
            Label("Donate", systemImage: "cup.and.saucer")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.help("Support SoundSwipe on Ko-fi").accessibilityLabel("Donate to SoundSwipe on Ko-fi")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(mixingLook ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6).padding(.trailing, -4)
            Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            donateLink
                .padding(.horizontal, 8).frame(height: 22)
                .background(Color.primary.opacity(0.07), in: Capsule())
            Button("Sound Settings…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).frame(height: 22).background(Color.primary.opacity(0.07), in: Capsule())
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var statusText: String {
        guard mixingLook else { return "Mixing off" }
        let count = audio.controlledApps.count
        return count == 0 ? "Mixing on" : "Mixing \(count) app\(count == 1 ? "" : "s")"
    }
    private func iconButton(_ symbol: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(active ? Color.orange : Color.secondary).frame(width: 20, height: 22)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
    private func percentage(_ value: Float) -> some View {
        Text("\(Int((value * 100).rounded()))%").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
            .frame(width: 38, alignment: .trailing).lineLimit(1)
    }
    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(error).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if audio.mixingNeedsRetry {
                Button("Retry") { audio.setMixing(true) }.controlSize(.small)
            }
            Button { audio.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    private func frequencyLabel(_ hz: Float) -> String { hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))" }
    private func balanceText(_ value: Float) -> String {
        let amount = Int((abs(value) * 100).rounded())
        return amount == 0 ? "Center" : "\(value < 0 ? "L" : "R") \(amount)"
    }
}

enum Theme {
    static let accent = Color(red: 0.24, green: 0.47, blue: 0.98)
}

private extension View {
    /// Borderless menu buttons flatten custom labels into NSPopUpButton text; a plain button style keeps the SwiftUI layout.
    func plainMenu() -> some View { menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden) }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
    }
}

/// SF Symbol with a safe fallback for symbols missing on older systems.
private struct DeviceIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "speaker.wave.2" : symbol)
            .font(.system(size: 14)).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

/// Positions along a slider track; kept separate so view bodies stay simple to type-check.
private struct TrackGeometry {
    static let thumb: CGFloat = 14
    let length: CGFloat
    let fraction: CGFloat
    /// Thumb center along the track axis, from the start edge.
    var position: CGFloat { Self.thumb / 2 + (length - Self.thumb) * fraction }
    var center: CGFloat { length / 2 }
    func fraction(at location: CGFloat) -> CGFloat { min(1, max(0, (location - Self.thumb / 2) / (length - Self.thumb))) }
}

private struct SliderThumb: View {
    var dot = false
    var body: some View {
        Circle().fill(Color.white).shadow(color: Color.black.opacity(0.35), radius: 1.5, y: 0.5)
            .overlay(Circle().fill(Theme.accent).frame(width: dot ? 5 : 0, height: dot ? 5 : 0))
            .frame(width: TrackGeometry.thumb, height: TrackGeometry.thumb)
    }
}

/// A graphic-EQ fader: drag or use VoiceOver adjust actions; the center line marks 0 dB.
private struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let label: String
    private var fraction: CGFloat { CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) }

    var body: some View {
        GeometryReader { geometry in fader(size: geometry.size) }
            .frame(width: 30)
            .help(String(format: "%+.1f dB", value))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(String(format: "%.1f decibels", value))
            .accessibilityAdjustableAction { direction in set(value + (direction == .increment ? 1 : -1)) }
    }
    private func fader(size: CGSize) -> some View {
        // Track coordinates run top to bottom; the value runs bottom to top.
        let track = TrackGeometry(length: size.height, fraction: 1 - fraction)
        let midX: CGFloat = size.width / 2
        let fillLength: CGFloat = abs(track.position - track.center)
        let fillMid: CGFloat = (track.position + track.center) / 2
        return ZStack {
            ForEach(0..<5, id: \.self) { tick in tickMark(tick, track: track, x: midX) }
            Capsule().fill(Color.primary.opacity(0.14)).frame(width: 4, height: size.height - TrackGeometry.thumb).position(x: midX, y: track.center)
            Capsule().fill(Theme.accent.opacity(0.85)).frame(width: 4, height: fillLength).position(x: midX, y: fillMid)
            SliderThumb(dot: true).position(x: midX, y: track.position)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            let position = Float(1 - track.fraction(at: drag.location.y))
            set(range.lowerBound + position * (range.upperBound - range.lowerBound))
        })
    }
    private func tickMark(_ tick: Int, track: TrackGeometry, x: CGFloat) -> some View {
        let isCenter = tick == 2
        let y: CGFloat = TrackGeometry.thumb / 2 + (track.length - TrackGeometry.thumb) * CGFloat(tick) / 4
        return Rectangle().fill(Color.primary.opacity(isCenter ? 0.35 : 0.12)).frame(width: isCenter ? 16 : 10, height: 1).position(x: x, y: y)
    }
    private func set(_ newValue: Float) { value = min(range.upperBound, max(range.lowerBound, newValue)) }
}

/// Left/right balance that fills outward from the center; double-click to center.
private struct BalanceSlider: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { geometry in bar(size: geometry.size) }
            .accessibilityElement()
            .accessibilityLabel("Balance")
            .accessibilityValue(value == 0 ? "Center" : "\(Int(abs(value) * 100)) percent \(value < 0 ? "left" : "right")")
            .accessibilityAdjustableAction { direction in set(value + (direction == .increment ? 0.1 : -0.1)) }
    }
    private func bar(size: CGSize) -> some View {
        let track = TrackGeometry(length: size.width, fraction: CGFloat((value + 1) / 2))
        let midY: CGFloat = size.height / 2
        let fillLength: CGFloat = abs(track.position - track.center)
        let fillMid: CGFloat = (track.position + track.center) / 2
        return ZStack {
            Capsule().fill(Color.primary.opacity(0.14)).frame(width: size.width - TrackGeometry.thumb, height: 4).position(x: track.center, y: midY)
            Capsule().fill(Theme.accent.opacity(0.85)).frame(width: fillLength, height: 4).position(x: fillMid, y: midY)
            Rectangle().fill(Color.primary.opacity(0.4)).frame(width: 1.5, height: 10).position(x: track.center, y: midY)
            SliderThumb().position(x: track.position, y: midY)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in set(Float(track.fraction(at: drag.location.x)) * 2 - 1) })
        .onTapGesture(count: 2) { value = 0 }
    }
    private func set(_ newValue: Float) { value = min(1, max(-1, newValue)) }
}

/// Post-processing peak as 8 LED segments on a -60…0 dB scale. Observes only the meter model, so updates stay local.
@available(macOS 14.2, *)
private struct SegmentMeter: View {
    @ObservedObject var levels: LevelMeters
    let id: String
    var body: some View {
        let peak = levels.values[id] ?? 0
        let fill = peak > 0 ? max(0, 1 + 20 * log10(peak) / 60) : 0
        let lit = Int((fill * 8).rounded())
        HStack(spacing: 1.5) {
            ForEach(0..<8) { segment in
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(segment < lit ? color(segment) : Color.primary.opacity(0.14))
                    .frame(width: 2.5, height: 12)
            }
        }.accessibilityHidden(true)
    }
    private func color(_ segment: Int) -> Color { segment >= 7 ? .red : segment >= 6 ? .orange : .green }
}
