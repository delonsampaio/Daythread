# Owner Custom Sync Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move owner-side shared-trip sync off `NSPersistentCloudKitContainer` (NSPCKC) and onto the existing custom `SharedSyncEngine`, using per-trip custom zones + zone-wide CKShares, so co-editing is real-time in both directions and the share lifecycle (stop-sharing, self-removal) is owned by our code.

**Architecture:** Each shared trip = one custom `CKRecordZone` named `Zone-<tripUUID>`, shared zone-wide via `CKShare(recordZoneID:)`. Owner syncs that zone against `privateCloudDatabase`; participant against `sharedCloudDatabase`; identical zone ID, identical `CD_`-format records (existing `CKRecordMapper` reused). Sharing a trip migrates its full object graph from the NSPCKC store into the detached `shared.sqlite` store (crash-safe: clone → upload → await → purge). Design doc: `docs/superpowers/specs/2026-06-03-owner-custom-sync-engine-design.md`.

**Tech Stack:** Swift 6 (MainActor-by-default module), Core Data (single `NSPersistentCloudKitContainer`, two stores), CloudKit (`CKModifyRecordZonesOperation`, `CKModifyRecordsOperation`, `CKFetchRecordZoneChangesOperation`, `CKShare`, `UICloudSharingController`).

**Testing note:** CloudKit operations are **device-only** (no simulator iCloud) and must be verified **detached from Xcode** (the debugger masks silent pushes). Unit tests cover the parts that don't touch the network: migration graph-cloning, push routing decisions, change-token namespacing, and `CloudKitService` orchestration via the existing `TripSharingBackend` stub. Build after every task with:
`xcodebuild build -scheme Daythread -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug`

---

## File Structure

**New files:**
- `Daythread/Services/SharedSync/SharedZoneSharing.swift` — manual zone + zone-wide CKShare creation/deletion, CKShare fetch/cache (replaces NSPCKC `share()`).
- `Daythread/Services/SharedSync/TripStoreMigrator.swift` — crash-safe graph move from NSPCKC store → shared store.
- `DaythreadTests/TripStoreMigratorTests.swift` — clone-graph correctness (in-memory store).
- `DaythreadTests/SharedSyncRoutingTests.swift` — push routing + token namespacing.

**Modified files:**
- `Daythread/Services/SharedSync/SharedSyncEngine.swift` — add private-DB pull/push loop, push routing, zone-deletion purge, CKShare caching.
- `Daythread/Services/CloudKitService.swift` — `shareTrip` orchestrates migrate→create→push; add `stopSharing`/`leaveShare` via new backend.
- `Daythread/Services/CloudKitTripSharingBackend.swift` — back onto `SharedZoneSharing` instead of NSPCKC `share()`.
- `Daythread/Persistence/PersistenceController.swift` — private-DB subscription; remove `waitForExportQuiescence`/quiescence observer + `pokeSyncPing`/`SyncPing`; migration-state plumbing.
- `Daythread/Persistence/Entities/Trip+CoreDataProperties.swift` (+ model) — add `migrationState` attribute.
- `Daythread/Services/SharedSync/CKRecordMapper.swift` — token/CKShare helpers if needed; **read/write record mapping stays unchanged**.
- `Daythread/Views/Timeline/GroupSyncSheet.swift` — present `UICloudSharingController` for owner (manage/stop) and participant (stop accessing); "Preparing Share…" state.
- Remove diagnostic `apply batch` log + keep push-coalescing (cleanup task).

---

## Phase 0 — Model + scaffolding

### Task 0.1: Add `migrationState` to Trip

**Files:**
- Modify: `Daythread/Daythread.xcdatamodeld` (Trip entity) — add `migrationState` Integer 16, default `0`.
- Modify: `Daythread/Persistence/Entities/Trip+CoreDataProperties.swift`

- [ ] **Step 1:** In the model, add `migrationState` (Integer 16, non-optional, default 0) to `Trip`. Add a Swift enum mirror.

```swift
// Trip+CoreDataProperties.swift (or a small Trip+Migration.swift)
enum TripMigrationState: Int16 {
    case none = 0      // lives in NSPCKC store, never shared
    case cloned = 1    // graph duplicated into shared store, not yet uploaded
    case uploaded = 2  // pushed to custom zone, NSPCKC originals not yet purged
    case done = 3      // fully on the custom store
}
extension Trip {
    var migration: TripMigrationState {
        get { TripMigrationState(rawValue: migrationState) ?? .none }
        set { migrationState = newValue.rawValue }
    }
}
```

- [ ] **Step 2:** Build. Expected: SUCCEEDS (lightweight migration adds the attribute).
- [ ] **Step 3:** Commit: `feat: add Trip.migrationState for custom-share migration`

### Task 0.2: Namespace change tokens by database scope

**Files:**
- Modify: `Daythread/Services/SharedSync/SharedSyncEngine.swift` (`loadToken`/`saveToken`)
- Modify: `Daythread/Daythread.xcdatamodeld` (`SyncState`) — add `databaseScope` String (default `"shared"`).
- Test: `DaythreadTests/SharedSyncRoutingTests.swift`

- [ ] **Step 1:** Write failing test: saving a token for `(scope: .private, zone: Z)` and `(scope: .shared, zone: Z)` yields two independent `SyncState` rows; loading each returns the matching token.
- [ ] **Step 2:** Run test → FAIL (predicate ignores scope).
- [ ] **Step 3:** Add `databaseScope` to `SyncState`; change `loadToken`/`saveToken` signatures to take a `CKDatabase.Scope` and include it in the predicate (`zoneName == %@ AND databaseScope == %@`). Default existing rows to `"shared"`.
- [ ] **Step 4:** Run test → PASS.
- [ ] **Step 5:** Build. Commit: `feat: namespace sync change-tokens by database scope`

---

## Phase 1 — Engine: private-DB pull/push + routing

### Task 1.1: Generalize fetch over a database + scope

**Files:**
- Modify: `Daythread/Services/SharedSync/SharedSyncEngine.swift`

- [ ] **Step 1:** Extract a private `fetchZone(_ zoneID:in db:scope:) async -> Int` that takes the `CKDatabase` and scope (currently hardcodes `sharedDB`). `fetchAllSharedZones` iterates the shared DB; add `fetchAllOwnedZones` iterating `privateCloudDatabase` for zones matching `Zone-*` (skip NSPCKC's `com.apple.coredata.cloudkit.zone`).
- [ ] **Step 2:** In `fetchZone`, on `CKError.zoneNotFound` (or `recordZoneWithIDWasDeletedBlock`): purge all shared-store objects for that zone's trip + delete the zone's `SyncState` rows. (Wire the actual purge in Task 4.2; here just branch + log.)
- [ ] **Step 3:** `startPeriodicSync` polls **both** `fetchAllSharedZones()` and `fetchAllOwnedZones()`; keep the `pendingFetch` coalescing for each.
- [ ] **Step 4:** Build. Commit: `feat: add owner private-DB pull loop to SharedSyncEngine`

### Task 1.2: Push routing (private vs shared DB)

**Files:**
- Modify: `Daythread/Services/SharedSync/SharedSyncEngine.swift` (`pushLocalChanges`)
- Test: `DaythreadTests/SharedSyncRoutingTests.swift`

- [ ] **Step 1:** Write failing test for a routing helper `databaseScope(forZone zoneID:) -> CKDatabase.Scope`: a zone whose `ownerName == CKCurrentUserDefaultName` → `.private`; otherwise `.shared`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the helper; in `pushLocalChanges`, group records by their zone and send each group to the routed database. (Records carry their zone via stored system fields / the trip's zone.)
- [ ] **Step 4:** Run → PASS. Build. Commit: `feat: route shared-store pushes to private or shared DB by zone ownership`

### Task 1.3: Private-DB subscription

**Files:**
- Modify: `Daythread/Services/CloudKitService.swift` (`ensureSharedDatabaseSubscription` → add private variant)
- Modify: `Daythread/Persistence/PersistenceController.swift` (push routing by `databaseScope`)

- [ ] **Step 1:** Add `ensurePrivateDatabaseSubscription()` — a `CKDatabaseSubscription` on `privateCloudDatabase` (silent, `shouldSendContentAvailable`). Register both subscriptions at launch.
- [ ] **Step 2:** In the push-notification handler, inspect `CKDatabaseNotification.databaseScope`: `.private` → `fetchAllOwnedZones()`; `.shared` → `fetchAllSharedZones()`.
- [ ] **Step 3:** Build. Commit: `feat: private-DB silent-push subscription for owner zones`

---

## Phase 2 — Manual sharing (zone + zone-wide CKShare)

### Task 2.1: SharedZoneSharing — create zone + share

**Files:**
- Create: `Daythread/Services/SharedSync/SharedZoneSharing.swift`

- [ ] **Step 1:** Implement `makeZoneShare(forTripID:) async throws -> CKShare`:
  1. `CKModifyRecordZonesOperation` saving `CKRecordZone(zoneID: Zone-<tripUUID> / CKCurrentUserDefaultName)` to private DB; await success.
  2. `let share = CKShare(recordZoneID: zoneID)`; set `title`; `publicPermission = .none`.
  3. `CKModifyRecordsOperation(recordsToSave: [share])`, `savePolicy = .ifServerRecordUnchanged`; await success; return share.
- [ ] **Step 2:** Implement `deleteZoneShare(forTripID:) async throws` — `CKModifyRecordZonesOperation(recordZoneIDsToDelete: [zoneID])` on private DB (stop-sharing).
- [ ] **Step 3:** Implement `fetchShare(forTripID:) async throws -> CKShare?` — cached encoded system fields first, else `CKFetchRecordsOperation` for the zone-wide share record ID.
- [ ] **Step 4:** Build. Commit: `feat: manual custom-zone + zone-wide CKShare creation`

### Task 2.2: Cache the CKShare from the pull loop

**Files:**
- Modify: `Daythread/Services/SharedSync/SharedSyncEngine.swift` (`fetchZone`)

- [ ] **Step 1:** When `recordZoneChanges` returns a `CKShare` record, persist its encoded system fields into the zone's `SyncState` (new `shareSystemFields` Data attr) so `fetchShare` can present the UI without a round-trip.
- [ ] **Step 2:** Build. Commit: `feat: cache zone-wide CKShare for the sharing UI`

---

## Phase 3 — Migration (crash-safe graph move)

### Task 3.1: TripStoreMigrator — clone graph

**Files:**
- Create: `Daythread/Services/SharedSync/TripStoreMigrator.swift`
- Test: `DaythreadTests/TripStoreMigratorTests.swift`

- [ ] **Step 1:** Failing test (in-memory container with two stores, or a stubbed coordinator): cloning a Trip with N days / M events into the shared store produces an identical graph (same attribute values, same relationship shape, each object assigned to the shared store, each with a `ckRecordName`); originals remain.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `cloneGraph(_ trip:) -> Trip` on the **viewContext (main queue)**: fetch the trip with `returnsObjectsAsFaults = false` + `relationshipKeyPathsForPrefetching` for all trip relationships; recursively insert duplicates, `context.assign(_, to: sharedStore)`, copy non-skipped attributes, mint/carry `ckRecordName`, rebuild relationships among the clones. Set `clone.migration = .cloned`.
- [ ] **Step 4:** Run → PASS. Build. Commit: `feat: TripStoreMigrator graph clone into shared store`

### Task 3.2: Migration orchestration (clone → upload → purge)

**Files:**
- Modify: `Daythread/Services/SharedSync/TripStoreMigrator.swift`

- [ ] **Step 1:** Implement `migrate(_ trip:) async throws -> Trip`:
  - Phase 1: `clone = cloneGraph(trip)`, save (state `.cloned`).
  - Phase 2: create the zone+share (Task 2.1), push the clone via the engine, await success; set `clone.migration = .uploaded`, save.
  - Phase 3: delete the original NSPCKC-store graph, save; set `clone.migration = .done`, save.
- [ ] **Step 2:** Implement `resumeInterruptedMigrations()` (call on launch): for any Trip in `.cloned` → re-run from Phase 2; `.uploaded` → re-run Phase 3; dedupe duplicate clones by `ckRecordName`.
- [ ] **Step 3:** Build. Commit: `feat: crash-safe trip migration orchestration + resume`

---

## Phase 4 — Wire orchestration + lifecycle

### Task 4.1: CloudKitService.shareTrip via migration + manual share

**Files:**
- Modify: `Daythread/Services/CloudKitService.swift`
- Modify: `Daythread/Services/CloudKitTripSharingBackend.swift`
- Test: existing `CloudKitService` tests (stub `TripSharingBackend`)

- [ ] **Step 1:** Update `TripSharingBackend` protocol: `makeShare` now migrates + creates the zone-wide share; add `stopSharing(tripID:)` and `existingShare(tripID:)`. Update the stub.
- [ ] **Step 2:** `CloudKitTripSharingBackend` delegates to `TripStoreMigrator` + `SharedZoneSharing`. Remove the detached-`share()` + `fetchShares` path.
- [ ] **Step 3:** `shareTrip` drops `waitForExportQuiescence`; calls `backend.makeShare` (which migrates), stamps `cloudKitShareID`, returns the share. Keep the graceful error path.
- [ ] **Step 4:** Run `CloudKitService` tests → PASS. Build. Commit: `feat: shareTrip migrates + creates custom zone-wide share`

### Task 4.2: Purge on zone deletion (participant side)

**Files:**
- Modify: `Daythread/Services/SharedSync/SharedSyncEngine.swift`

- [ ] **Step 1:** Implement the purge branched in Task 1.2 Step 2: delete all shared-store objects belonging to the deleted zone's trip (match by stored zone in system fields), delete the zone's `SyncState` rows, post `dayThreadRemoteChangeDidApply`.
- [ ] **Step 2:** Build. Commit: `feat: purge local trip when its shared zone is deleted (stop-sharing)`

### Task 4.3: UICloudSharingController for owner + participant

**Files:**
- Modify: `Daythread/Views/Timeline/GroupSyncSheet.swift`
- Possibly add: a small `UIViewControllerRepresentable` wrapper.

- [ ] **Step 1:** Owner: "Manage / Stop Sharing" presents `UICloudSharingController(share:container:)` from the cached `CKShare`; implement delegate (`itemTitle`, save/stop). On stop, call `backend.stopSharing` (delete zone) + clear `cloudKitShareID`.
- [ ] **Step 2:** Participant: the "Trip is shared" button presents the same controller, which shows system "Stop Accessing Share". After removal, the zone leaves the shared DB → purge path (Task 4.2) fires.
- [ ] **Step 3:** Add the "Preparing Share…" blocking state on the trip while `migration != .done`.
- [ ] **Step 4:** Build. Commit: `feat: present UICloudSharingController for manage/stop/leave`

---

## Phase 5 — Cleanup + verification

### Task 5.1: Remove dead NSPCKC-sharing plumbing

**Files:**
- Modify: `Daythread/Persistence/PersistenceController.swift` — remove `waitForExportQuiescence`, `activeExportCount`, the export-count observer, `pokeSyncPing`, `lastPingAt`; remove `SyncPing` entity from the model.
- Modify: `Daythread/Services/SharedSync/CKRecordMapper.swift` — remove the `apply batch` diagnostic log (keep coalescing + orphan `.error`).

- [ ] **Step 1:** Delete the listed members + `SyncPing` entity. Build (fix references).
- [ ] **Step 2:** Commit: `chore: remove NSPCKC-sharing quiescence/ping plumbing`

### Task 5.2: Docs + FAQ

**Files:**
- Modify: `Daythread/.../HelpView.swift` and `docs/index.html` (per standing rule: update on any feature/nav change).

- [ ] **Step 1:** Update co-editing copy if behavior/messaging changed (real-time, stop-sharing, leaving a trip).
- [ ] **Step 2:** Commit: `docs: update co-editing help + site copy`

### Task 5.3: On-device verification (detached from Xcode)

- [ ] Owner add/edit/delete → appears on participant in real time, foreground.
- [ ] Participant edit → appears on owner in real time.
- [ ] Owner Stop Sharing → trip purges on participant (no reopen).
- [ ] Participant "Stop Accessing" → trip purges locally; owner sees participant `.removed`.
- [ ] Migration crash recovery: kill the app mid-share at each phase; relaunch resumes to `.done` with no duplicates/loss.
- [ ] Owner second device picks up a freshly shared trip after migration.

---

## Self-Review notes
- **Spec coverage:** every design section maps to a task (engine private path → P1; manual share → P2; migration → P3; lifecycle/UI → P4; cleanup → P5). ✔
- **Type consistency:** `TripMigrationState` (0.1), `databaseScope` (0.2), `makeZoneShare`/`deleteZoneShare`/`fetchShare` (2.1) referenced consistently downstream. ✔
- **Device-only caveat:** TDD applied to non-network logic (migration clone, routing, tokens, orchestration); CloudKit ops verified on-device (5.3). ✔
