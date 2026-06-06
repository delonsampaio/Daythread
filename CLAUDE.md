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

## Two-store sync architecture (Path A)

Core Data has two stores under one coordinator:
- `private.sqlite` — synced by NSPersistentCloudKitContainer (NSPCKC default zone)
- `shared.sqlite` — custom `SharedSyncEngine`, per-trip `Zone-<tripUUID>` (NSPCKC options severed)

**Any new managed object on a shared trip MUST end up in `shared.sqlite`.** Either call
`context.assign(obj, to: sharedStore)` (see `TripStoreMigrator`) or create it already linked
to a shared-store parent *before* save (Core Data infers the store from a to-one relationship).
A new object with no relationship and no `assign()` defaults into the **private** store → its
object graph then spans two zones → NSPCKC export fails with `NSCocoaErrorDomain Code=134060`
("Objects related to … are assigned to multiple zones"), resets, and **halts ALL CloudKit sync
until that object is deleted**. The custom engine's `isSharedSynced` also skips mis-stored
objects (never pushed → invisible to co-editors). This bit `AddEditEventSheet`'s `TransitDetails`
(fixed e89ef8f). Related: `CKRecordMapper.zoneIDForNewChild` recurses up the parent chain so a
new child pushed in the same batch as its new parent resolves its zone from an already-synced
grandparent.

## Debugging "slowness / freezes"

- `Publishing changes from background threads is not allowed` is **constant CloudKit-sync noise**,
  not proof of a freeze — it fires regardless of the symptom. Don't chase it as a perf cause.
- A frozen main thread can't animate a sheet in. A window that appears but is **blank/stale** is a
  SwiftUI state-timing bug (use `.sheet(item:)`, not `.sheet(isPresented:) + if let`), not a block.
  (fixed d179343)
- Time Profiler shows ~0 CPU during a *blocked* (not busy) main thread — "no samples" ≠ "nothing
  wrong." Confirm a real block with a hang monitor (bounce a probe off `DispatchQueue.main` from a
  background queue) before proposing performance fixes.

## iOS patterns

For CoreData/CloudKit rules and SwiftUI pitfalls, invoke the relevant skill:
- `/ios-coredata-cloudkit` — @NSManaged defaults, isAlive guards, database scope
- `/ios-swiftui-patterns` — geometry loops, keyboard avoidance, TabView, NavigationSplitView
