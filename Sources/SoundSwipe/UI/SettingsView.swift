import SwiftUI
import ServiceManagement

@available(macOS 14.2, *)
struct SettingsView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var preferences: Preferences
    @ObservedObject var shortcuts: ShortcutManager
    @State private var recording: ShortcutAction?
    @State private var monitor: Any?
    @State private var message: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Open SoundSwipe at login", isOn: Binding(get: { launchAtLogin }, set: { value in
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            if SMAppService.mainApp.status == .requiresApproval { message = "Allow SoundSwipe in System Settings → General → Login Items." }
                        } catch { message = error.localizedDescription }
                    }))
                    Text("SoundSwipe lives in your menu bar. Drag the app to Applications before enabling launch at login.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("General") }
                Section {
                    Toggle("Turn on Mix apps when SoundSwipe opens", isOn: $preferences.mixAtLaunch)
                    Text("Mixing runs only for apps with an adjusted volume or a custom output. Turn off Mix apps to release every route immediately.").font(.callout)
                    Button("Reset all application volumes and routes") { audio.resetMixes() }
                    Button("Open audio permissions") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                } header: { Text("Audio") }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "switch.2") }
            Form {
                Section {
                    ForEach(ShortcutAction.allCases) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            Button(recording == action ? "Press shortcut…" : preferences.shortcuts[action.rawValue]?.label ?? "Record shortcut") { beginRecording(action) }
                                .frame(minWidth: 145).accessibilityLabel("Record shortcut for \(action.title)")
                            Button { preferences.shortcuts.removeValue(forKey: action.rawValue); shortcuts.register(preferences.shortcuts) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).disabled(recording != nil || preferences.shortcuts[action.rawValue] == nil).accessibilityLabel("Clear shortcut for \(action.title)")
                        }
                    }
                } header: { Text("Global shortcuts") }
                Text("Use Command, Control, or Option with a key. Shortcuts work while other apps are open. Escape cancels recording. No Accessibility permission required.").font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
                if let error = shortcuts.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            VStack(spacing: 15) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 64)).foregroundStyle(.blue.gradient)
                Text("SoundSwipe").font(.system(size: 26, weight: .semibold))
                Text("Small app. Sound in your hands.").foregroundStyle(.secondary)
                Text("Version \(AppInfo.version) · Preview").font(.caption).foregroundStyle(.secondary)
                Text("Native macOS audio control. Open source under the MIT license.\nNo analytics, accounts, or network service.").font(.callout).multilineTextAlignment(.center)
                Divider().padding(.horizontal, 45)
                Text("Made by Hitesh Gupta").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    if let url = Preferences.profileURL(preferences.github, hosts: ["github.com", "www.github.com"]) { Link("GitHub", destination: url) }
                    if let url = Preferences.profileURL(preferences.twitter, hosts: ["x.com", "twitter.com", "www.x.com", "www.twitter.com"]) { Link("X", destination: url) }
                    if let url = AppInfo.repository { Link("Source code", destination: url) }
                }.font(.caption)
                Text("Inspired by Background Music and SoundSource.\nAn independent project; not affiliated with either.").font(.system(size: 10)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("About", systemImage: "info.circle") }
        }.padding(12).frame(width: 560, height: 430)
            .onDisappear { endRecording() }
    }
    private func beginRecording(_ action: ShortcutAction) {
        endRecording(); recording = action; message = nil; shortcuts.clear()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { endRecording(); return nil }
            guard let binding = ShortcutManager.binding(from: event) else { message = "Include Command, Control, or Option."; return nil }
            if preferences.shortcuts.contains(where: { $0.key != action.rawValue && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) { message = "That shortcut is assigned to another action."; return nil }
            preferences.shortcuts[action.rawValue] = binding
            endRecording(); return nil
        }
    }
    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil
        shortcuts.register(preferences.shortcuts)
    }
}
