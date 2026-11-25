# GarbageMan

A small native macOS app that finds and clears the junk that quietly fills a Mac's disk: caches, logs, developer build data, old simulators and leftover app files. It lives in your menu bar and sends what it cleans to the Trash, so you can get things back.

## Features

- **Quick Clean**: sizes and clears user caches and logs, browser caches (Safari, Chrome, Firefox, Arc, Brave), Xcode DerivedData, Archives and Device Support, npm, Yarn, pnpm, pip and Gem caches. The Gem cache is only RubyGems' spec cache and downloaded `.gem` files; installed gems and `~/.gem/credentials` are left alone. Developer items are grouped in their own Developer section, which only appears when at least one of those tools or folders exists on the Mac.
  - **Unavailable Simulators**: removes simulator devices whose runtime is no longer installed, using Apple's own `xcrun simctl delete unavailable`.
  - **Old Temp Build Folders**: your own folders in `/private/tmp` that nothing has touched for 2+ days (old build and test output). Folders belonging to running tools and the system are skipped.
- **Uninstaller**: drag in an app to find its leftover files (preferences, caches, containers, launch agents) and remove them together.
- **Disk Inspector**: browse folder sizes to see where your space went.
- **Menu bar monitor**: disk, memory, CPU and battery at a glance.

Everything except Empty Trash and simulator deletion goes to the Trash, never a permanent delete.

## Requirements

- macOS 14 or later
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build

## Build

```bash
xcodegen generate
xcodebuild -project GarbageMan.xcodeproj -scheme GarbageMan -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/GarbageMan.app
```

Run the tests:

```bash
xcodebuild -project GarbageMan.xcodeproj -scheme GarbageMan -derivedDataPath build test
```

`scripts/make-dmg.sh` builds a Release DMG.

## License

MIT. See [LICENSE](LICENSE).
