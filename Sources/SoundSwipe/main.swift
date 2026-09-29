import AppKit
import SwiftUI
import CoreAudio
import Combine

@available(macOS 14.2, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let preferences = Preferences()
    lazy var audio = AudioController(preferences: preferences)
    let shortcuts = ShortcutManager()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var settings: NSWindow?
    private var scrollMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "SoundSwipe"
        item.button?.toolTip = "SoundSwipe — click for controls, scroll for volume, right-click for more"
        item.button?.target = self; item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        audio.$outputMuted.removeDuplicates().sink { [weak self] muted in self?.updateIcon(muted: muted) }.store(in: &cancellables)
        // Status item windows belong to this app, so a local monitor sees scrolls over the icon without extra permissions.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.item.button?.window, event.window === window else { return event }
            self.scrollVolume(event); return nil
        }
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(audio: audio, preferences: preferences, openSettings: { [weak self] in self?.openSettings() }))
        shortcuts.perform = { [weak self] action in
            guard let self else { return }
            switch action {
            case .panel: self.togglePanel()
            case .mute: self.audio.toggleMute()
            case .quieter: if let v = self.audio.outputVolume { self.audio.setOutputVolume(v - 0.05) }
            case .louder: if let v = self.audio.outputVolume { self.audio.setOutputVolume(v + 0.05) }
            case .nextOutput: self.audio.nextOutput()
            }
        }
        shortcuts.register(preferences.shortcuts)
        if CommandLine.arguments.contains("--show") { togglePanel() }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            let host = NSHostingView(rootView: PanelView(audio: audio, preferences: preferences, openSettings: {}))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 368, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; window.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                host.layoutSubtreeIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
                }
                NSApp.terminate(nil)
            }
        }
    }
    private func updateIcon(muted: Bool) {
        item.button?.image = NSImage(systemSymbolName: muted ? "speaker.slash" : "waveform", accessibilityDescription: muted ? "SoundSwipe, output muted" : "SoundSwipe")
        item.button?.image?.isTemplate = true
    }
    private func scrollVolume(_ event: NSEvent) {
        guard let volume = audio.outputVolume else { return }
        let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 300 : event.scrollingDeltaY / 30
        let delta = event.isDirectionInvertedFromDevice ? -raw : raw
        guard delta != 0 else { return }
        audio.setOutputVolume(volume + Float(delta))
    }
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true { showQuickMenu() } else { togglePanel() }
    }
    private func showQuickMenu() {
        if popover.isShown { popover.performClose(nil) }
        audio.refresh()
        let menu = NSMenu()
        let outputs = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        outputs.submenu = NSMenu()
        for device in audio.outputs {
            let entry = NSMenuItem(title: device.name, action: #selector(chooseOutput(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = Int(device.id); entry.state = device.id == audio.outputID ? .on : .off
            outputs.submenu?.addItem(entry)
        }
        menu.addItem(outputs)
        menu.addItem(withTitle: audio.outputMuted ? "Unmute" : "Mute", action: #selector(toggleMute), keyEquivalent: "").target = self
        menu.addItem(withTitle: audio.mixingEnabled ? "Turn Off Mix Apps" : "Turn On Mix Apps", action: #selector(toggleMixing), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit SoundSwipe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
    @objc private func chooseOutput(_ sender: NSMenuItem) { audio.selectOutput(AudioObjectID(sender.tag)) }
    @objc private func toggleMute() { audio.toggleMute() }
    @objc private func toggleMixing() { audio.setMixing(!audio.mixingEnabled) }
    @objc private func showSettings() { openSettings() }
    func popoverDidShow(_ notification: Notification) { audio.setMetering(true) }
    func popoverDidClose(_ notification: Notification) { audio.setMetering(false) }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            audio.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func openSettings() {
        popover.performClose(nil)
        if settings == nil {
            let host = NSHostingController(rootView: SettingsView(audio: audio, preferences: preferences, shortcuts: shortcuts))
            let window = NSWindow(contentViewController: host)
            window.title = "SoundSwipe Settings"; window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false; window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        audio.shutdown(); shortcuts.shutdown()
    }
}

if #available(macOS 14.2, *) {
    if CommandLine.arguments.contains("--diagnostics") {
        let devices = AudioDevice.discover()
        let output = Hardware.read(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
        let report: [String: Any] = ["version": AppInfo.version, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "devices": devices.map { ["name": $0.name, "input": $0.hasInput, "output": $0.hasOutput] as [String: Any] },
            "defaultOutputPresent": devices.contains { $0.id == output }, "audioProcesses": AudioApplication.discover().count]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    } else {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
} else {
    fputs("SoundSwipe requires macOS 14.2 or later.\n", stderr)
    exit(1)
}
