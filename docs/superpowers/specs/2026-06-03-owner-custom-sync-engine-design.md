# Owner Custom Sync Engine — Design

**Date:** 2026-06-03
**Status:** Approved approach; pending spec review → implementation plan.

## Goal

Make the **owner** of a shared trip sync through the existing custom `SharedSyncEngine`
(instant `CKModifyRecordsOperation` push) instead of `NSPersistentCloudKitContainer`
(NSPCKC). This removes NSPCKC from **all shared data** and fixes the confirmed
root cause of laggy co-editing: NSPCKC defers the owner's shared-zone export
because the `processing` background mode was removed (App Store ITMS-90771), so
`BGTaskScheduler` returns `notPermitted` and exports only flush when the device
locks/backgrounds.

As a bonus, owning the CKShare lifecycle (instead of NSPCKC) also cleanly fixes
the two other open bugs: **stop-sharing not propagating to participants** and
**participant self-removal being a no-op**.

## Confirmed decisions

1. **Clean break on existing shares.** Trips already shared via NSPCKC `share()`
   are NOT migrated. New shares use the custom-zone path; an old-style share must
   be stopped and re-shared (participants re-accept). Acceptable given the tiny
   live user base and constant re-sharing during testing.
2. **Once shared, a trip stays in the custom store.** After "Stop Sharing", the
   trip remains in `shared.sqlite`, synced across the owner's own devices via the
   private-DB custom zone (just with no participants). No reverse migration.

## Architecture

### Zone-wide sharing, one custom zone per trip
- Each shared trip gets its own `CKRecordZone` named `Zone-<tripUUID>` (deterministic).
- Sharing uses **`CKShare(recordZoneID:)`** (zone-wide), so every record saved to
  that zone is shared as a unit — no per-record `record.parent` wiring.
- Stop-sharing = delete the zone. Participants detect zone deletion and purge.

### Database asymmetry (owner vs participant)
| Role | Database | Zone |
|------|----------|------|
| **Owner** | `privateCloudDatabase` | custom `Zone-<tripUUID>` |
| **Participant** | `sharedCloudDatabase` | same `Zone-<tripUUID>` |

The engine must run **two pull/push loops**: owner shares against the **private**
DB; joined shares against the **shared** DB. Implications:
- **Subscriptions:** a `CKDatabaseSubscription` on the **private** DB (owner) and
  the existing one on the **shared** DB (participant).
- **Push routing:** when a local shared-store object changes, push to the private
  DB if the current user owns the trip's zone, else the shared DB.
- **Change tokens:** namespace `SyncState` by database scope + zone (private+zone
  vs shared+zone) so the two loops don't clobber each other's tokens.

### Record format: reuse `CD_` + existing `CKRecordMapper` (unchanged)
The engine already round-trips `CD_<Entity>` / `CD_<attr>` records for participant→
owner push. Owner→participant uses the **same** format. The entire participant
**pull path and mapper stay unchanged** — only the owner's push, share creation,
migration, and lifecycle are new. recordName-as-relationship stays as-is.

## Components

### New
- **`SharedSyncEngine` private-DB path** — pull (`recordZoneChanges` on private DB
  custom zones the owner created) + push routing + private DB subscription +
  scoped change tokens.
- **Manual share creation** (replaces `CloudKitTripSharingBackend.makeShare`):
  1. Save the custom zone (`CKModifyRecordZonesOperation`) to the **private** DB.
  2. Create `CKShare(recordZoneID:)`, set `title`, `publicPermission = .none`.
  3. Save the share with `CKModifyRecordsOperation`, `savePolicy = .ifServerRecordUnchanged`.
  4. Push the trip graph (already in the custom store post-migration) via the engine.
- **Migration** (`PersistenceController` or a `TripMigrator`): move a trip's full
  object graph from the NSPCKC store into the custom store (crash-safe).
- **Stop-sharing**: delete the custom zone from the private DB.
- **Participant self-removal**: present `UICloudSharingController`; the system's
  built-in "Stop Accessing Share" removes the participant.
- **CKShare retrieval/cache** — without NSPCKC we don't get the `CKShare` "for
  free" for the management UI. A zone-wide share is returned as a record by
  `recordZoneChanges`, so cache its encoded system fields per-zone (in `SyncState`)
  on every pull; the UI presents `UICloudSharingController` from the cached share,
  falling back to a targeted `CKFetchRecordsOperation` if absent.

### Changed
- `CloudKitService.shareTrip` — orchestrate migration → zone/share creation →
  engine push, instead of NSPCKC `share()` + quiescence wait.
- `GroupSyncSheet` / "Trip is shared" button — present `UICloudSharingController`
  for both owner (manage/stop) and participant (stop accessing).
- Remove `waitForExportQuiescence` / detached-`share()` plumbing (no longer needed).

### Unchanged
- `CKRecordMapper` (read + write paths), participant pull, echo-suppression,
  push-coalescing, NSPCKC for private/unshared trips.

## Migration sequence (crash-safe)

Both stores share one `NSPersistentCloudKitContainer` coordinator, so this is an
in-context clone + reassign, NOT a cross-container copy. Core Data forbids
cross-store relationships, so the **whole graph moves together**. The clone runs
on the **viewContext (main queue / `@MainActor`)** — same isolation as the engine,
so there is no cross-actor MOC access and no Swift 6 concurrency warning. The
clone fetch sets `returnsObjectsAsFaults = false` and prefetches the trip's
relationship key paths so the full graph is materialized before traversal.

```
State flag per trip: migrationState ∈ {none, cloned, uploaded, done}

Phase 1 — CLONE (state → cloned)
  Deep-copy Trip + all related objects into new managed objects assigned to the
  shared store; carry over a stable ckRecordName for each; keep originals intact.

Phase 2 — UPLOAD (state → uploaded)
  Engine pushes the cloned graph to the new custom zone in the PRIVATE DB.
  AWAIT definitive CKModifyRecordsOperation .success.

Phase 3 — PURGE (state → done)
  Delete the original NSPCKC-store objects + save. NSPCKC tombstones only its own
  zone; the custom-zone records are isolated and untouched.
```

**Safety rationale:** NSPCKC deletes propagate only within
`com.apple.coredata.cloudkit.zone`; our `Zone-<tripUUID>` is a separate zone NSPCKC
does not manage, so the just-uploaded records cannot be erased.

**Crash recovery (on launch):**
- `cloned` but not `uploaded`: clone exists in shared store but not on server →
  re-run upload; if a duplicate clone is detected, dedupe by ckRecordName.
- `uploaded` but not `done`: server has it, originals still in NSPCKC store →
  re-run purge.
- **UI during the window:** when the user taps Share, immediately put the trip
  into a blocking **"Preparing Share…"** state (interaction disabled) until the
  Phase 3 save completes, then refresh the UI onto the new shared-store object.
  Cleaner than runtime fetch-request filtering and avoids any double-display.

## Lifecycle signals

- **Stop sharing (owner):** `CKModifyRecordZonesOperation(recordZoneIDsToDelete:)`
  on private DB. Participant's next `recordZoneChanges` yields
  `recordZoneWithIDWasDeletedBlock` or `CKError.zoneNotFound` → engine purges the
  trip's local records from `shared.sqlite` and clears that zone's token. (Our
  `fetchZone` catch must special-case `.zoneNotFound`.)
- **Self-removal (participant):** `UICloudSharingController` "Stop Accessing" →
  zone leaves the participant's shared DB → same purge path as above.
- **Owner sees removal:** push on the owner's private-DB zone → engine pulls the
  updated `CKShare`; `share.participants` shows the participant `.removed`.

## Open risks / watch-items
- **Owner multi-device "ghost" flicker:** after device A migrates, device B's
  NSPCKC processes the tombstone and removes the trip, then B's custom pull
  re-inserts it from the private-DB zone — the trip briefly vanishes and reappears.
  Acceptable (minor visual flicker). **Local-only metadata:** the only unsynced
  attributes are `ekEventIdentifier` / `hasReminder` / `showInCalendar`, which are
  legitimately device-local (B has its own Calendar), so dropping them on B during
  the ghost-delete is correct, not a regression. **Action:** audit the model to
  confirm no *other* device-local-but-critical attribute exists; if one does, carry
  it across the delete→reinsert on B.
- **Swift 6 isolation:** migration's graph copy must run on the viewContext's main
  queue; engine pushes already hop to `@MainActor`. No cross-actor MOC access.
- **Duplicate-prevention during migration window** (see crash recovery).
- **`UICloudSharingController` with a manually-minted zone-wide share** — verify the
  invite UI + acceptance round-trips without NSPCKC (Gemini says yes; confirm on device).

## Testing
- Device-only (CloudKit). Test **detached from Xcode** (debugger masks pushes).
- Scenarios: owner add/edit/delete shows on participant in real time (foreground);
  participant edits show on owner; stop-sharing purges participant; participant
  self-removal purges locally + owner sees `.removed`; migration crash-recovery at
  each phase; owner second device picks up a freshly shared trip.
