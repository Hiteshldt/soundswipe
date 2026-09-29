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
    @State private var listHeight: CGFloat = 0
    static let width: CGFloat = 360
    private let accent = Color(red: 0.24, green: 0.43, blue: 0.95)

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 10) {
                outputCard
                inputCard
            }.padding(.horizontal, 12)
            appsHeader.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            appsList
            if let error = audio.error { errorBanner(error).padding(.horizontal, 12).padding(.bottom, 10) }
            Divider()
            footer
        }
        .frame(width: Self.width)
        .background(.regularMaterial)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 30, height: 30).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            Text("SoundSwipe").font(.system(size: 14, weight: .semibold))
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 24, height: 24) }
                .buttonStyle(.plain).help("Settings and keyboard shortcuts").accessibilityLabel("Open settings")
        }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var outputCard: some View {
        card {
            sectionLabel("OUTPUT", icon: "speaker.wave.2")
            devicePicker(isOutput: true)
            if let volume = audio.outputVolume {
                HStack(spacing: 8) {
                    iconButton(audio.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: audio.outputMuted, label: audio.outputMuted ? "Unmute output" : "Mute output") { audio.toggleMute() }
                    Slider(value: Binding(get: { Double(audio.outputVolume ?? volume) }, set: { audio.setOutputVolume(Float($0)) }), in: 0...1)
                        .controlSize(.small).accessibilityLabel("Output volume")
                    percentage(audio.outputMuted ? 0 : volume)
                }
            } else {
                note("This device sets its own volume.", icon: "info.circle")
            }
        }
    }

    private var inputCard: some View {
        card {
            HStack(spacing: 6) {
                sectionLabel("INPUT", icon: "mic")
                Spacer(minLength: 8)
                let users = audio.microphoneUsers
                if !users.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("In use by \(users.map(\.name).formatted(.list(type: .and)))").lineLimit(1).truncationMode(.tail)
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                        .help(users.map(\.name).joined(separator: ", ")).accessibilityElement(children: .combine)
                }
            }
            devicePicker(isOutput: false)
            HStack(spacing: 8) {
                iconButton(audio.inputMuted ? "mic.slash.fill" : "mic.fill", active: audio.inputMuted, label: audio.inputMuted ? "Unmute microphone" : "Mute microphone") { audio.toggleInputMute() }
                if let volume = audio.inputVolume {
                    Slider(value: Binding(get: { Double(audio.inputVolume ?? volume) }, set: { audio.setInputVolume(Float($0)) }), in: 0...1)
                        .controlSize(.small).accessibilityLabel("Input level")
                    percentage(audio.inputMuted ? 0 : volume)
                } else {
                    Text(audio.inputMuted ? "Muted" : "Level set by this device").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var appsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionLabel("APPS", icon: "square.stack.3d.up")
                Spacer()
                Toggle("Mix", isOn: Binding(get: { audio.mixingEnabled }, set: { audio.setMixing($0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                    .help("Mixing applies your per-app volume, EQ, and output. Turn off to restore normal audio instantly.")
            }
            if !audio.mixingEnabled && !audio.applications.isEmpty {
                Text("Adjust any app to start mixing. macOS asks for audio access once.")
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
            }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 18)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(audio.applications) { app in appRow(app) }
                }.padding(.horizontal, 12).padding(.bottom, 12)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            }
            .frame(height: min(max(listHeight, 60), 340))
            .onPreferenceChange(HeightKey.self) { listHeight = $0 }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(audio.mixingEnabled ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6).padding(.trailing, -4)
            Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Sound Settings…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Menu {
                Button("Settings…", action: openSettings)
                Divider()
                Button("Quit SoundSwipe") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis") }
                .plainMenu().fixedSize().accessibilityLabel("More options")
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var statusText: String {
        guard audio.mixingEnabled else { return "Mixing off" }
        let count = audio.controlledApps.count
        return count == 0 ? "Mixing on" : "Mixing \(count) app\(count == 1 ? "" : "s")"
    }

    // MARK: App row

    private func appRow(_ app: AudioApplication) -> some View {
        let mix = audio.mix(for: app)
        let isExpanded = expanded.contains(app.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Group {
                    if let icon = app.icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
                }.frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    activity(app)
                }.layoutPriority(1)
                Spacer(minLength: 4)
                outputMenu(app, mix: mix)
                Button { withAnimation(.easeInOut(duration: 0.15)) { if isExpanded { expanded.remove(app.id) } else { expanded.insert(app.id) } } } label: {
                    Image(systemName: "slider.vertical.3").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(mix.eqActive || abs(mix.balance) > 0.01 ? accent : .secondary)
                        .frame(width: 22, height: 22).background(isExpanded ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help("Equalizer and balance").accessibilityLabel("\(isExpanded ? "Hide" : "Show") equalizer for \(app.name)")
            }
            HStack(spacing: 8) {
                iconButton(mix.muted ? "speaker.slash.fill" : "speaker.wave.1.fill", active: mix.muted, label: "\(mix.muted ? "Unmute" : "Mute") \(app.name)") {
                    audio.updateMix(app) { $0.muted.toggle() }
                }
                Slider(value: Binding(get: { Double(audio.mix(for: app).volume) }, set: { value in
                    // Snap to 100% so the unchanged position is easy to find on a 0–200% slider.
                    let volume = abs(value - 1) < 0.04 ? 1 : Float(value)
                    audio.updateMix(app) { $0.volume = volume; $0.muted = false }
                }), in: 0...Double(AppMix.maxVolume))
                    .controlSize(.small).tint(mix.volume > 1.001 ? .orange : accent)
                    .accessibilityLabel("\(app.name) volume").help("100% is unchanged. Above 100% boosts with a limiter.")
                percentage(mix.muted ? 0 : mix.volume)
            }
            // Saved settings are shown but not applied while mixing is off.
            .opacity(audio.mixingEnabled ? 1 : 0.6)
            if audio.controlledApps.contains(app.id) {
                LevelBar(levels: audio.levels, id: app.id).padding(.leading, 30).padding(.trailing, 48)
            }
            if isExpanded { equalizer(app, mix: mix) }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func activity(_ app: AudioApplication) -> some View {
        HStack(spacing: 6) {
            if app.isPlaying { Label("Playing", systemImage: "speaker.wave.2.fill") }
            if app.isRecording { Label("Mic", systemImage: "mic.fill").foregroundStyle(.orange) }
            if !app.isActive { Text("Idle") }
        }
        .labelStyle(CompactLabel())
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }

    private func outputMenu(_ app: AudioApplication, mix: AppMix) -> some View {
        let routed = mix.outputUID.flatMap { uid in audio.outputs.first { $0.uid == uid } }
        return Menu {
            Button { audio.updateMix(app) { $0.outputUID = nil } } label: {
                if mix.outputUID == nil { Label("System Output", systemImage: "checkmark") } else { Text("System Output") }
            }
            Divider()
            ForEach(audio.outputs) { device in
                Button { audio.updateMix(app) { $0.outputUID = device.uid } } label: {
                    if mix.outputUID == device.uid { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
            Divider()
            Button("Reset \(app.name)") { audio.updateMix(app) { $0 = AppMix() } }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: routed == nil ? "hifispeaker" : "hifispeaker.fill")
                Text(routed?.name ?? "System").lineLimit(1).truncationMode(.middle)
            }.font(.system(size: 10)).foregroundStyle(routed == nil ? Color.secondary : accent)
        }
        .plainMenu().frame(maxWidth: 96).fixedSize(horizontal: false, vertical: true)
        .help(routed.map { "\(app.name) plays on \($0.name)" } ?? "\(app.name) follows the system output")
    }

    private func equalizer(_ app: AudioApplication, mix: AppMix) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 2)
            HStack {
                Text("Equalizer").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(EQPreset.allCases) { preset in
                        Button { audio.updateMix(app) { $0.eq = preset.bands } } label: {
                            if EQPreset.matching(mix.eq) == preset { Label(preset.title, systemImage: "checkmark") } else { Text(preset.title) }
                        }
                    }
                } label: { Text(EQPreset.matching(mix.eq)?.title ?? "Custom").font(.system(size: 11)) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            ForEach(Array(["Bass", "Mid", "Treble"].enumerated()), id: \.offset) { index, title in
                parameterRow(title, value: Binding(get: { audio.mix(for: app).eq[index] }, set: { value in
                    audio.updateMix(app) { $0.eq[index] = abs(value) < 0.5 ? 0 : (value * 2).rounded() / 2 }
                }), range: -AppMix.eqRange...AppMix.eqRange, text: decibels(mix.eq[index]))
            }
            parameterRow("Balance", value: Binding(get: { audio.mix(for: app).balance }, set: { value in
                audio.updateMix(app) { $0.balance = abs(value) < 0.05 ? 0 : value }
            }), range: -1...1, text: balanceText(mix.balance))
        }
    }

    private func parameterRow(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, text: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            Slider(value: value, in: range).controlSize(.mini).accessibilityLabel(title)
            Text(text).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: Components

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
    }
    private func iconButton(_ symbol: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(active ? Color.orange : Color.secondary).frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
    private func percentage(_ value: Float) -> some View {
        Text("\(Int((value * 100).rounded()))%").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing).lineLimit(1)
    }
    private func devicePicker(isOutput: Bool) -> some View {
        Menu {
            ForEach(isOutput ? audio.outputs : audio.inputs) { device in
                Button { if isOutput { audio.selectOutput(device.id) } else { audio.selectInput(device.id) } } label: {
                    if device.id == (isOutput ? audio.outputID : audio.inputID) { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(isOutput ? audio.outputName : audio.inputName).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.plainMenu().accessibilityLabel(isOutput ? "Output device" : "Input device")
    }
    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(error).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { audio.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    private func decibels(_ value: Float) -> String { value == 0 ? "0 dB" : String(format: "%+.1f dB", value).replacingOccurrences(of: ".0 ", with: " ") }
    private func balanceText(_ value: Float) -> String {
        let amount = Int((abs(value) * 100).rounded())
        return amount == 0 ? "Center" : "\(value < 0 ? "L" : "R") \(amount)"
    }
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

/// Post-gain peak on a -60…0 dB scale. Observes only the meter model, so updates stay local.
@available(macOS 14.2, *)
private struct LevelBar: View {
    @ObservedObject var levels: LevelMeters
    let id: String
    var body: some View {
        let peak = levels.values[id] ?? 0
        let fill = CGFloat(peak > 0 ? max(0, 1 + 20 * log10(peak) / 60) : 0)
        GeometryReader { geometry in
            Capsule().fill(.quaternary).overlay(alignment: .leading) {
                Capsule().fill(peak > 0.97 ? Color.orange : Color.green.opacity(0.85)).frame(width: geometry.size.width * fill)
            }
        }.frame(height: 3).animation(.linear(duration: 0.05), value: fill).accessibilityHidden(true)
    }
}
