// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SoundSwipe",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SoundSwipe", targets: ["SoundSwipe"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include"),
        .executableTarget(name: "SoundSwipe", dependencies: ["AudioDSP"],
                          linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("Carbon")]),
        .testTarget(name: "SoundSwipeTests", dependencies: ["SoundSwipe", "AudioDSP"])
    ]
)
