# Contributing

Build with a matching Swift 6.0+ toolchain and macOS SDK, then run `./scripts/test.sh` and `./scripts/build.sh`. Open `Package.swift` in Xcode if preferred.

Keep changes scoped. UI and audio state belong on the main actor. The real-time C callback must not allocate, block, log, access files, or call Swift/Objective-C. Every audio resource needs a tested cleanup path for partial initialization, normal stop, and device loss.

Include relevant tests and manual audio evidence for routing/DSP changes. File bugs with macOS version, architecture, device type/sample rate, steps, and expected/actual behavior. Avoid private audio, serial numbers, and unrelated logs. See docs/TESTING.md for the release matrix.

By contributing, you agree that your contributions are licensed under the project’s MIT license. Do not copy code or assets from differently licensed or proprietary audio utilities.
