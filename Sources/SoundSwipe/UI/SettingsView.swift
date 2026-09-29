import SwiftUI
import ServiceManagement

@available(macOS 14.2, *)
struct SettingsView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var preferences: Preferences
    @ObservedObject var shortcuts: ShortcutManager
    @State private var tab: Int
    @State private var recording: ShortcutAction?
    @State private var monitor: Any?
    @State private var message: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(audio: AudioController, preferences: Preferences, shortcuts: ShortcutManager, initialTab: Int = 0) {
        self.audio = audio; self.preferences = preferences; self.shortcuts = shortcuts
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            shortcutList.tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(1)
            about.tabItem { Label("About", systemImage: "info.circle") }.tag(2)
        }
        .frame(width: 500, height: 440)
        .onDisappear { endRecording() }
    }

    private var general: some View {
        Form {
            Section("General") {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    Text("Open SoundSwipe at login")
                    Text("Move SoundSwipe to Applications first.")
                }
            }
            Section("Mixing") {
                Toggle(isOn: $preferences.mixAtLaunch) {
                    Text("Turn on mixing when SoundSwipe opens")
                    Text("Restores your per-app volumes, EQ, and outputs automatically.")
                }
                LabeledContent {
                    Button("Reset All") { audio.resetMixes() }
                } label: {
                    Text("Per-app settings")
                    Text("Clears every saved volume, EQ, balance, and output.")
                }
                LabeledContent {
                    Button("Open…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                } label: {
                    Text("System audio access")
                    Text("Required for per-app control. Audio never leaves your Mac.")
                }
            }
            if let message { Text(message).font(.callout).foregroundStyle(.orange) }
        }.formStyle(.grouped)
    }

    private var shortcutList: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            Button(recording == action ? "Type shortcut…" : preferences.shortcuts[action.rawValue]?.label ?? "Record") { beginRecording(action) }
                                .frame(minWidth: 120).monospacedDigit().accessibilityLabel("Record shortcut for \(action.title)")
                            Button { preferences.shortcuts.removeValue(forKey: action.rawValue); shortcuts.register(preferences.shortcuts) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                                .opacity(preferences.shortcuts[action.rawValue] == nil ? 0 : 1)
                                .disabled(recording != nil || preferences.shortcuts[action.rawValue] == nil)
                                .accessibilityLabel("Clear shortcut for \(action.title)")
                        }
                    }
                }
            } header: { Text("Global shortcuts") } footer: {
                Text("Use ⌘, ⌃, or ⌥ with a key. Shortcuts work in any app. Esc cancels. No Accessibility permission needed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message { Text(message).font(.callout).foregroundStyle(.orange) }
            if let error = shortcuts.error { Text(error).font(.callout).foregroundStyle(.orange) }
        }.formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("SoundSwipe").font(.system(size: 22, weight: .semibold))
            Text("Version \(AppInfo.version) · Preview").font(.callout).foregroundStyle(.secondary)
            Text("Per-app volume, EQ, and routing for your Mac.\nFree and open source under the MIT license. No analytics or network access.")
                .font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            Spacer().frame(height: 6)
            HStack(spacing: 14) {
                if let url = AppInfo.repository { Link("Source Code", destination: url) }
                if let url = AppInfo.repository?.appendingPathComponent("issues") { Link("Report an Issue", destination: url) }
            }.font(.callout)
            Spacer()
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("Made by Hitesh Gupta")
                    if let url = Preferences.profileURL(preferences.github, hosts: ["github.com", "www.github.com"]) { Text("·"); Link("GitHub", destination: url) }
                    if let url = Preferences.profileURL(preferences.twitter, hosts: ["x.com", "twitter.com", "www.x.com", "www.twitter.com"]) { Text("·"); Link("X", destination: url) }
                }
                Text("Inspired by Background Music and SoundSource. Not affiliated with either.").foregroundStyle(.tertiary)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = SMAppService.mainApp.status == .requiresApproval ? "Allow SoundSwipe in System Settings → General → Login Items." : nil
        } catch { message = error.localizedDescription }
    }
    private func beginRecording(_ action: ShortcutAction) {
        endRecording(); recording = action; message = nil; shortcuts.clear()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { endRecording(); return nil }
            guard let binding = ShortcutManager.binding(from: event) else { message = "Include ⌘, ⌃, or ⌥."; return nil }
            if preferences.shortcuts.contains(where: { $0.key != action.rawValue && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) {
                message = "That shortcut is already used by another action."; return nil
            }
            preferences.shortcuts[action.rawValue] = binding
            message = nil
            endRecording(); return nil
        }
    }
    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil
        shortcuts.register(preferences.shortcuts)
    }
}
