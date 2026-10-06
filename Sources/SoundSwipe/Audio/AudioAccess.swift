import Foundation

/// System audio capture access (Privacy & Security → Screen & System Audio Recording →
/// System Audio Recording Only). macOS has no public API to check or request it, and tap creation
/// does not reliably fail when access is missing, so this uses the TCC calls that
/// audio-capture apps commonly use. If they are unavailable, mixing falls back to the system prompt.
enum AudioAccess: Equatable {
    case granted, denied, notDetermined, unavailable

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let preflight: Preflight? = framework.flatMap { dlsym($0, "TCCAccessPreflight") }.map { unsafeBitCast($0, to: Preflight.self) }
    private static let request: Request? = framework.flatMap { dlsym($0, "TCCAccessRequest") }.map { unsafeBitCast($0, to: Request.self) }

    static var current: AudioAccess {
        guard let preflight else { return .unavailable }
        switch preflight(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }
    /// Shows the macOS prompt when access was never decided; otherwise reports the saved decision.
    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard let request else { Task { @MainActor in completion(true) }; return }
        request(service, nil) { granted in Task { @MainActor in completion(granted) } }
    }
}
