import SwiftUI
import CoreAudio

@available(macOS 14.2, *)
struct PanelView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var preferences: Preferences
    var openSettings: () -> Void
    private let accent = Color(red: 0.24, green: 0.43, blue: 0.95)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 19, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 36, height: 36).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SoundSwipe").font(.system(size: 15, weight: .semibold))
                    Text("A little more control.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Settings and keyboard shortcuts").accessibilityLabel("Open settings")
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("OUTPUT", icon: "speaker.wave.2")
                        devicePicker(isOutput: true)
                        HStack(spacing: 10) {
                            Button { audio.toggleMute() } label: { Image(systemName: audio.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 22) }
                                .buttonStyle(.plain).help("Mute output").accessibilityLabel(audio.outputMuted ? "Unmute output" : "Mute output")
                            if let volume = audio.outputVolume {
                                Slider(value: Binding(get: { Double(audio.outputVolume ?? volume) }, set: { audio.setOutputVolume(Float($0)) }), in: 0...1)
                                    .accessibilityLabel("Output volume")
                                percentage(volume)
                            } else { Text("Volume controlled by this device").font(.caption).foregroundStyle(.secondary); Spacer() }
                        }.tint(accent)
                    }.padding(14).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("INPUT", icon: "mic")
                        devicePicker(isOutput: false)
                        if let volume = audio.inputVolume {
                            HStack(spacing: 10) {
                                Image(systemName: "mic.fill").frame(width: 22).foregroundStyle(.secondary)
                                Slider(value: Binding(get: { Double(audio.inputVolume ?? volume) }, set: { audio.setInputVolume(Float($0)) }), in: 0...1).accessibilityLabel("Input gain")
                                percentage(volume)
                            }.tint(accent)
                        }
                    }.padding(.horizontal, 14)
                    Divider()
                    HStack {
                        sectionLabel("APPLICATIONS", icon: "square.stack.3d.up")
                        Spacer()
                        Toggle("Mix apps", isOn: Binding(get: { audio.mixingEnabled }, set: { audio.setMixing($0) }))
                            .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                    }
                    if !audio.mixingEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your apps. Your balance.", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .medium))
                            Text("Turn on Mix apps to adjust individual volumes and send apps to different outputs. macOS will request system-audio access when you change an app.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("Audio stays on your Mac.").font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                            TextField("Find an audio app", text: $audio.search).textFieldStyle(.plain).font(.system(size: 12))
                        }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        if audio.filteredApplications.isEmpty {
                            Text(audio.search.isEmpty ? "Play audio in an app to see it here." : "No matching apps.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 15)
                        }
                        ForEach(audio.filteredApplications) { app in appRow(app) }
                    }
                    if let error = audio.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(error).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button { audio.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                        }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }.frame(maxHeight: 480)
            Divider()
            HStack(spacing: 6) {
                Circle().fill(audio.mixingEnabled ? Color.green : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                Text(audio.mixingEnabled ? "\(audio.controlledApps.count) app\(audio.controlledApps.count == 1 ? "" : "s") adjusted" : "System audio").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Sound settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                Menu { Button("Quit SoundSwipe") { NSApp.terminate(nil) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).accessibilityLabel("More options")
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }.frame(width: 368).background(.regularMaterial)
    }
    private func percentage(_ value: Float) -> some View { Text("\(Int(value * 100))%").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing) }
    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
    }
    private func devicePicker(isOutput: Bool) -> some View {
        Menu {
            ForEach(isOutput ? audio.outputs : audio.inputs) { device in
                Button { if isOutput { audio.selectOutput(device.id) } else { audio.selectInput(device.id) } } label: {
                    if device.id == (isOutput ? audio.outputID : audio.inputID) { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
        } label: {
            HStack { Text(isOutput ? audio.outputName : audio.inputName).font(.system(size: 13, weight: .medium)).lineLimit(1); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            .contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel(isOutput ? "Output device" : "Input device")
    }
    private func appRow(_ app: AudioApplication) -> some View {
        let mix = preferences.mixes[app.id] ?? AppMix()
        return VStack(spacing: 8) {
            HStack(spacing: 9) {
                Group { if let icon = app.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "app.fill").resizable().foregroundStyle(.secondary) } }.frame(width: 25, height: 25)
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button("System output") { audio.updateMix(app) { $0.outputUID = nil } }
                    Divider()
                    ForEach(audio.outputs) { device in Button(device.name) { audio.updateMix(app) { $0.outputUID = device.uid } } }
                    Divider()
                    Button("Reset this app") { audio.updateMix(app) { $0 = AppMix() } }
                } label: {
                    Text(mix.outputUID.flatMap { uid in audio.outputs.first { $0.uid == uid }?.name } ?? "System").font(.system(size: 10)).lineLimit(1).frame(maxWidth: 100)
                }.menuStyle(.borderlessButton).fixedSize().help("Output for \(app.name)")
            }
            HStack(spacing: 9) {
                Button { audio.updateMix(app) { $0.muted.toggle() } } label: { Image(systemName: mix.muted ? "speaker.slash.fill" : "speaker.wave.1.fill").frame(width: 25).foregroundStyle(mix.muted ? accent : .secondary) }.buttonStyle(.plain).accessibilityLabel("\(mix.muted ? "Unmute" : "Mute") \(app.name)")
                Slider(value: Binding(get: { Double((preferences.mixes[app.id] ?? AppMix()).volume) }, set: { value in
                    // Snap to 100% so the unchanged position is easy to find on a 0–200% slider.
                    let volume = abs(value - 1) < 0.04 ? 1 : Float(value)
                    audio.updateMix(app) { $0.volume = volume; $0.muted = false }
                }), in: 0...Double(AppMix.maxVolume)).tint(mix.volume > 1.001 ? .orange : accent)
                    .accessibilityLabel("\(app.name) volume").help("Above 100% boosts with a soft limiter")
                percentage(mix.muted ? 0 : mix.volume)
            }
            if audio.controlledApps.contains(app.id) { LevelBar(levels: audio.levels, id: app.id).padding(.leading, 34).padding(.trailing, 47) }
        }.padding(12).background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
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
