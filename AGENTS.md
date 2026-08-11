# AGENTS.md

## Cursor Cloud specific instructions

### Platform: this is a macOS-only app and CANNOT be built or run on the Linux Cloud VM

`JarvisNotch` is a native **macOS** menu-bar / "notch" desktop utility written in Swift. There is
**no backend, server, database, or web/mobile client** — it is a single self-contained AppKit/SwiftUI
`.app` bundle. Cursor Cloud VMs run **Linux (Ubuntu x86_64)**, so this project cannot be built, linted,
tested, or run here. Do not spend time trying to install a toolchain to build it on the cloud VM.

Concrete reasons (verified during setup):

- Sources import Apple-only frameworks unavailable on Linux: `Cocoa`, `AppKit`, `SwiftUI`, `IOKit`,
  `AVFoundation`, `CoreLocation`. See `JarvisNotch/*.swift`.
- `MediaService.swift` `dlopen`s the private `/System/Library/PrivateFrameworks/MediaRemote.framework`,
  which only exists on macOS.
- `JarvisNotch/build.sh` compiles with `swiftc ... -framework Cocoa -framework SwiftUI -framework IOKit
  -sdk "$(xcrun --show-sdk-path)"`. Both `xcrun` and the macOS SDK are macOS-only.
- The checked-in binaries (`JarvisNotch/JarvisNotch.app/Contents/MacOS/JarvisNotch` and
  `JarvisNotch/TestApp`) are `Mach-O arm64` executables and fail with `Exec format error` on the Linux VM.

There is **no package manager and no dependency manifest** (`Package.swift`, `package.json`, etc.),
so there is nothing to install. The environment update script is intentionally a no-op.

### How to build / run (requires a macOS machine — not the cloud VM)

On a real macOS host with the Xcode command-line tools installed:

- Build: `cd JarvisNotch && ./build.sh` (produces `JarvisNotch.app`).
- Run: `open JarvisNotch.app`.

There are no automated tests or lint configuration in this repo. `TestApp.swift` is a standalone
diagnostic app (also macOS-only).

### Developer-specific hardcoded paths (gotcha)

`AppDelegate.swift` and `MediaService.swift` / `NotchStateManager.swift` hardcode a log path
`/Users/miguelsoberano/codigojarvis/JarvisNotch/log.txt`. Writes are done with `try?` so they fail
silently on other machines; this is expected and not an error to "fix" as part of environment setup.
