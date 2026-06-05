# Daythread — Project Guide

## Build & Test

- **Simulator:** iPhone 17 Pro (not 16)
- **Run tests:**
  ```bash
  xcodebuild test -project Daythread.xcodeproj -scheme Daythread \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"
  ```
- Always run `xcodebuild` before claiming tests pass — SourceKit shows false "Cannot find type X" errors for cross-file Swift symbols. Trust the build, not the editor.
- **MainActor-by-default isolation** — new types doing background work need explicit `nonisolated` or `Task.detached`.

## CloudKit sync testing

Test live sync **detached from Xcode**: run → Stop → launch from home screen. The debugger masks silent push delivery.

## iOS patterns

For CoreData/CloudKit rules and SwiftUI pitfalls, invoke the relevant skill:
- `/ios-coredata-cloudkit` — @NSManaged defaults, isAlive guards, database scope
- `/ios-swiftui-patterns` — geometry loops, keyboard avoidance, TabView, NavigationSplitView
