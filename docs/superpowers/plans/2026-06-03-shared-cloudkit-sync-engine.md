# Shared-Database Custom CloudKit Sync Engine (Path A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give CKShare *participants* reliable, near-real-time sync of shared trips by replacing `NSPersistentCloudKitContainer`'s deferred shared-database mirroring with a custom CloudKit engine, while leaving the private store (and the owner's sharing/export) on NSPCKC.

**Architecture:** Hybrid. The `private.sqlite` store stays fully managed by NSPCKC (own data + trips you own and share — including exporting owner edits and importing participant edits via the private-DB subscription). The `shared.sqlite` store is **severed** from NSPCKC (`cloudKitContainerOptions = nil`) and becomes a plain local store that our `SharedSyncEngine` keeps in sync with the CKShare zones via raw CloudKit: `CKFetchRecordZoneChangesOperation` (pull, fired immediately on push — no dasd deferral) and `CKModifyRecordsOperation` (push participant edits, formatted to match NSPCKC's CKRecord encoding so the owner imports them).

**Tech Stack:** Swift 6 (MainActor-by-default module), Core Data (`NSPersistentCloudKitContainer`, multi-store), CloudKit (`CKDatabase`, `CKFetchRecordZoneChangesOperation`, `CKModifyRecordsOperation`, `CKAcceptSharesOperation`, `CKServerChangeToken`), iOS 26.

---

## ⚠️ Top risks (read before starting)

1. **CKRecord-format mimicry (highest risk).** For the owner's NSPCKC to import participant edits, our pushed records must match NSPCKC's private encoding *exactly*: record type names (`CD_Trip` / `CD_TripEvent` …), field key prefixes (`CD_…`), the separate `CDMR…` records NSPCKC uses to encode to-many relationships, and `encodedSystemFields` round-tripping. This is undocumented and must be reverse-engineered from the CloudKit Dashboard against records NSPCKC actually created. **Phase 3 is gated on confirming this format empirically.**
2. **Regression risk.** Severing `shared.sqlite` from NSPCKC *removes* the currently-working participant→owner export. Both pull (Phase 2) and push (Phase 3) must land before this ships, or co-editing regresses.
3. **Cross-store relationships crash.** Core Data forbids relationships spanning `private.sqlite` and `shared.sqlite`. All shared-trip object creation must occur against objects fetched from the shared store. Verified in Phase 4.
4. **Token/empty-store desync.** Change tokens live in a `SyncState` entity *inside* `shared.sqlite` (not UserDefaults) so wiping the store wipes the tokens.

**Rollout discipline:** keep the existing NSPCKC shared-store path behind a build flag (`USE_CUSTOM_SHARED_SYNC`) until Phases 2+3 are proven on two physical devices in TestFlight, so we can revert instantly.

---

## Phase 0 — Reconnaissance (no app code)

### Task 0.1: Capture NSPCKC's exact CKRecord format
**Files:** none (CloudKit Dashboard + notes)

- [ ] In CloudKit Console (Development), with an existing shared trip, open the share's custom zone and export/inspect one record of each type: Trip, TripDay, TripEvent, TransitDetails, TripMember, TripDocument, TripExpense, LodgingInfo, PreTripTask.
- [ ] Record for each: exact **record type name**, every **field key** (prefix, casing), how **to-one** relationships are stored (CKReference field + action), and how **to-many** relationships are stored (look for `CDMR_<relationship>` companion records).
- [ ] Note how **blobs** (coverImageData, documentData, receiptImageData, avatarData) are stored (CKAsset vs inline) and the field keys.
- [ ] Note the **zone ID** naming (`com.apple.coredata.cloudkit.share.<UUID>`) and who owns it.
- [ ] Write findings to `docs/superpowers/specs/2026-06-03-nspckc-ckrecord-format.md`. **This file is the contract Phase 3 implements against.** If the format can't be pinned down here, stop and re-evaluate Path A.

---

## Phase 1 — Sever the shared store (behind a flag)

### Task 1.1: Add the feature flag
**Files:**
- Modify: `Daythread/Persistence/PersistenceController.swift`

- [ ] **Step 1:** Add a compile-time flag near the top of `PersistenceController`:

```swift
/// While true, shared.sqlite is detached from NSPCKC and synced by SharedSyncEngine.
/// Flip to false to fall back to the (broken-for-participants) NSPCKC shared mirroring.
nonisolated static let useCustomSharedSync = true
```

- [ ] **Step 2:** Commit.

### Task 1.2: Conditionally sever the shared store
**Files:**
- Modify: `Daythread/Persistence/PersistenceController.swift` (`addSharedStore()`)

- [ ] **Step 1:** In `addSharedStore()`, when `Self.useCustomSharedSync` is true, set `sharedDescription.cloudKitContainerOptions = nil` (keep history tracking on; the engine uses persistent history to detect local participant edits to push). Leave the NSPCKC path intact when the flag is false.
- [ ] **Step 2:** Build (`xcodebuild -scheme Daythread -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`). Expected: SUCCEEDS.
- [ ] **Step 3:** Run on device; confirm the app launches and private-store trips still sync. Shared-with-me trips will temporarily stop updating (expected until Phase 2). Commit.

---

## Phase 2 — Pull: custom shared-zone fetch (participant sees owner edits live)

### Task 2.1: SyncState entity for change tokens
**Files:**
- Modify: `Daythread/.../Daythread.xcdatamodeld/Daythread.xcdatamodel/contents`
- Create: `Daythread/Persistence/Entities/SyncState+CoreDataClass.swift`
- Create: `Daythread/Persistence/Entities/SyncState+CoreDataProperties.swift`

- [ ] **Step 1:** Add `SyncState` entity (NOT syncable to CloudKit — it's local bookkeeping): `zoneName: String`, `ownerName: String`, `changeTokenData: Binary`, `lastSyncedAt: Date`. Add to `<elements>`.
- [ ] **Step 2:** Add the manual class + properties files matching the existing entity pattern.
- [ ] **Step 3:** Build. Expected: SUCCEEDS. Commit.

### Task 2.2: CKRecord → Core Data mapper (read path)
**Files:**
- Create: `Daythread/Services/SharedSync/CKRecordMapper.swift`

- [ ] **Step 1:** Implement `func apply(_ records: [CKRecord], deletions: [CKRecord.ID], into context: NSManagedObjectContext)` that, per the format doc from Task 0.1, upserts each CKRecord into the matching Core Data entity in `shared.sqlite` (match on the `id`/recordName), resolves CKReference relationships to local objects, downloads CKAssets into the blob attributes, and deletes tombstoned records. All work inside `context.perform`.
- [ ] **Step 2:** Unit-test the mapper with synthetic CKRecords against an in-memory store (verify upsert, relationship wiring, delete). Run: `xcodebuild test …`. Expected: PASS.
- [ ] **Step 3:** Commit.

### Task 2.3: SharedSyncEngine — fetch
**Files:**
- Create: `Daythread/Services/SharedSync/SharedSyncEngine.swift`

- [ ] **Step 1:** Implement `fetchChanges(in zoneID: CKRecordZone.ID) async` — loads the stored `CKServerChangeToken` from `SyncState`, runs `CKFetchRecordZoneChangesOperation` on `container.sharedCloudDatabase`, feeds results to `CKRecordMapper.apply(...)`, saves the new token to `SyncState`, then posts `.dayThreadRemoteChangeDidApply` on the main thread.
- [ ] **Step 2:** Implement `fetchAllSharedZones() async` — enumerates shared zones via `CKFetchDatabaseChangesOperation` and calls `fetchChanges` per zone.
- [ ] **Step 3:** Commit (no trigger wired yet).

### Task 2.4: Trigger fetch on push, launch, foreground
**Files:**
- Modify: `Daythread/Services/ShareAcceptance.swift` (`didReceiveRemoteNotification`)
- Modify: `Daythread/DaythreadApp.swift` (launch + scenePhase .active)
- Remove: the Path B `SyncPing` poke from `didReceiveRemoteNotification` (superseded)

- [ ] **Step 1:** On `didReceiveRemoteNotification`, if the push is for the shared DB, call `SharedSyncEngine.shared.fetchAllSharedZones()` immediately (this is the whole point — our fetch runs now, not deferred).
- [ ] **Step 2:** Call `fetchAllSharedZones()` at launch and on `scenePhase` → `.active`.
- [ ] **Step 3:** Build + run on two devices. **Checkpoint:** participant (B) timeline updates live when owner (A) edits, no relaunch. Commit.

---

## Phase 3 — Push: participant edits → shared zone (highest risk)

### Task 3.1: Detect local shared-store edits
**Files:**
- Create: `Daythread/Services/SharedSync/SharedChangeTracker.swift`

- [ ] **Step 1:** Observe `NSManagedObjectContextDidSave` for the shared store (or use persistent history on `shared.sqlite`) to collect inserted/updated/deleted objects belonging to shared trips.
- [ ] **Step 2:** Commit.

### Task 3.2: Core Data → CKRecord encoder (matching NSPCKC format)
**Files:**
- Modify: `Daythread/Services/SharedSync/CKRecordMapper.swift`

- [ ] **Step 1:** Implement `func ckRecord(for object: NSManagedObject, in zoneID:) -> CKRecord` producing the **exact** record type, field keys, CKReferences (`.deleteSelf` to mirror cascade), `CDMR` relationship records, and CKAssets per the Task 0.1 format doc. Round-trip `encodedSystemFields` when updating existing records.
- [ ] **Step 2:** Test: encode an object, decode it back via the read mapper, assert round-trip equality. PASS.
- [ ] **Step 3:** Commit.

### Task 3.3: SharedSyncEngine — push with conflict handling
**Files:**
- Modify: `Daythread/Services/SharedSync/SharedSyncEngine.swift`

- [ ] **Step 1:** Implement `pushLocalChanges() async` — `CKModifyRecordsOperation` targeting the owner's zone, `savePolicy = .ifServerRecordUnchanged`.
- [ ] **Step 2:** Handle `.serverRecordChanged`: merge per-field (ObjectTrump / last-writer-wins on timestamp), re-push the merged record.
- [ ] **Step 3:** Wire `SharedChangeTracker` → `pushLocalChanges()`.
- [ ] **Step 4:** Build + run on two devices. **Checkpoint:** owner (A) sees participant (B) edits (this replaces the export we severed in Phase 1). Commit.

---

## Phase 4 — Share acceptance + object creation correctness

### Task 4.1: Manual share acceptance
**Files:**
- Modify: `Daythread/Services/ShareAcceptance.swift` (`userDidAcceptCloudKitShareWith`)

- [ ] **Step 1:** Replace `acceptShareInvitations(from:into:)` with a raw `CKAcceptSharesOperation` on the `CKShare.Metadata`; on success, extract `rootRecordID` + `share.recordID.zoneID` and call `SharedSyncEngine.fetchChanges(in: zoneID)`.
- [ ] **Step 2:** Build + run: accept a fresh share on B; the trip appears and syncs live. Commit.

### Task 4.2: Ensure new shared objects are created in the shared store
**Files:**
- Modify: event/expense/document creation sites (e.g. `AddEditEventSheet.swift`, `AddExpenseSheet.swift`, …)

- [ ] **Step 1:** Audit every `Entity(context:)` insertion for shared trips; ensure the new object is associated with the shared-store `Trip`/`TripDay` (Core Data assigns the store via the related object). Add an assertion/guard against linking private↔shared.
- [ ] **Step 2:** Test on device: participant adds an event/expense/document to a shared trip — no crash, syncs to owner. Commit.

---

## Phase 5 — Cutover & cleanup

- [ ] **Task 5.1:** Two-device TestFlight validation of the full matrix (owner→participant, participant→owner, add/edit/delete, blobs, offline→online, conflict). Deploy CloudKit schema (incl. SyncState is local-only, so no shared schema change) — verify owner zone format unaffected.
- [ ] **Task 5.2:** Remove obsolete debug logging and the Path B `SyncPing` entity/poke. Keep `daythreadLog` error-level lines.
- [ ] **Task 5.3:** Update `HelpView.swift` + `docs/index.html` if co-editing behavior/《sync》messaging changes (per project rule).
- [ ] **Task 5.4:** Remove the `useCustomSharedSync` fallback flag once stable.

---

## Self-review notes
- **Both directions required before ship** (Phase 2 + 3) — Phase 1 alone regresses participant→owner. Flag-gated to avoid shipping half.
- **Phase 0 is a hard gate**: if NSPCKC's CKRecord format can't be pinned down, Phase 3 (push) is infeasible and we should reconsider (e.g. accept "syncs on open" instead).
- **No cross-store relationships** — enforced in Task 4.2.
- Tokens in `SyncState` inside `shared.sqlite`, not UserDefaults.
