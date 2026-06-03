# NSPersistentCloudKitContainer CKRecord Format — Daythread

**Purpose:** The contract the custom shared-sync engine (Path A, Phase 3) must produce so the owner's NSPCKC imports participant edits cleanly. Below is the **expected** format from known NSPCKC behavior. Items marked **🔎 VERIFY** must be confirmed against real records in the CloudKit Console (Development → container `iCloud.com.delonsampaio.daythread`) before Phase 3 is built.

> How to verify: CloudKit Console → **Schema → Record Types** (gives record types + field keys), and **Data → Records** on the Shared DB / share zone (gives a real record's values, especially relationship + asset fields).

---

## 1. Record types
NSPCKC prefixes each Core Data entity with `CD_`:

| Core Data entity | CKRecord type |
|---|---|
| Trip | `CD_Trip` |
| TripDay | `CD_TripDay` |
| TripEvent | `CD_TripEvent` |
| TransitDetails | `CD_TransitDetails` |
| TripMember | `CD_TripMember` |
| TripDocument | `CD_TripDocument` |
| TripExpense | `CD_TripExpense` |
| LodgingInfo | `CD_LodgingInfo` |
| PreTripTask | `CD_PreTripTask` |

**🔎 VERIFY:** the exact casing/prefix on the Record Types page (confirm it's `CD_` and not e.g. `CD_TripEvent` vs `TripEvent`).

## 2. Attribute fields
Each Core Data attribute → a CKRecord field keyed `CD_<attributeName>`, same value type. Examples for `CD_TripEvent`:
`CD_id` (String/UUID), `CD_title`, `CD_startTime` (Date/Timestamp), `CD_endTime`, `CD_notes`, `CD_sortOrder` (Int64), `CD_isPrivate` (Int64 0/1), `CD_visibleToMemberIDs`, `CD_categoryRaw`, `CD_latitude`/`CD_longitude` (Double), `CD_isTimeLocked`, `CD_addedByAppleUserID`.

Notes:
- **Booleans** are stored as **`INT(64)`** 0/1 (VERIFIED: `CD_isPrivate`, `CD_isTimeLocked`, etc.).
- **Device-local fields ARE present in the schema** (`CD_ekEventIdentifier`, `CD_hasReminder`, `CD_showInCalendar`) even though the model marks them `syncable="NO"` — likely legacy/retained. **The engine must NOT write them** (they're device-specific; propagating them would clobber the other device's local state). Skip on push; ignore on pull.
- **Legacy/unknown fields** also present that aren't in the current model (e.g. `CD_moveReceipt`, `CD_participantNames` on Trip, `CD_category` BYTES on TripEvent). CloudKit schema is additive, so old fields persist. **Ignore any field not in the current Core Data model.**
- `CD_id` (STRING) carries the Core Data `id` UUID as a string — used for our local upsert match (VERIFIED present).

## 3. Entity-name field
Each record carries a field **`CD_entityName`** = the Core Data entity name (e.g. `"TripEvent"`). **🔎 VERIFY present and exact key.**

## 4. To-one relationships (VERIFIED — differs from initial assumption)
**CONFIRMED in dashboard:** relationships are stored as a **`STRING`** field `CD_<relationshipName>` whose value is the **recordName of the related record** — NOT a `CKReference`, and there is **no `.deleteSelf` action**.

- `CD_TripEvent.CD_day` → **STRING** = recordName of the `CD_TripDay` record
- `CD_TripDay.CD_trip` → **STRING** = recordName of the `CD_Trip` record
- `CD_TripEvent.CD_transitDetails` → **STRING** = recordName of the `CD_TransitDetails` record

**Implications for the engine:**
- **Push encoder:** set `record["CD_day"] = <parent recordName string>` (not a reference). Simpler than references.
- **Cascade deletes are NOT server-side** (no `.deleteSelf`). When a participant deletes a parent, we must either delete the children explicitly in the same `CKModifyRecordsOperation`, or rely on the owner's Core Data cascade rule firing when it imports the parent deletion. **Decide in Phase 3** (prefer explicit child deletion to be safe).
- **Pull mapper:** resolve `CD_day` (a recordName string) to the local TripDay by matching on recordName. Requires we persist each pulled record's recordName alongside its object (store it, since `CD_id` ≠ recordName).

**🔎 STILL NEEDED — a sample record's VALUES** (the Query button was disabled — select the share zone under "Select a Zone" first, or we capture this during Phase 2 pull): the **recordName format** NSPCKC uses (so participant-created records mint compatible names), and confirm `CD_day`'s value is indeed a recordName string. Low risk to defer to the Phase 2 pull (we'll log the first fetched records).

## 5. To-many relationships
**Not stored on the parent.** Derived from the inverse to-one reference (Section 4). Our model's to-manys (Trip.days, TripDay.events, Trip.documents/expenses/lodging/members/preTripTasks) all have inverse to-ones, so **no `CDMR_*` companion records are expected.** **🔎 VERIFY** there are no `CDMR_*` record types in the schema.

## 6. Large-value overflow & blobs (VERIFIED)
**CONFIRMED:** every field has a companion `CD_<field>_ckAsset` (ASSET) alongside the inline field (e.g. `CD_name` STRING + `CD_name_ckAsset` ASSET; `CD_coverImageData` BYTES + `CD_coverImageData_ckAsset` ASSET). This is NSPCKC's **large-value overflow**: a value under the inline size limit goes in the plain field with `_ckAsset` null; a large value (big blobs/long strings) goes in `_ckAsset` as a `CKAsset` with the plain field null.

**Engine rule:** write small strings/scalars to `CD_<field>`; write large binaries (cover images, document data, receipts, avatars) to `CD_<field>_ckAsset` as a `CKAsset`. On pull, read whichever is populated. **🔎 confirm the exact size threshold during Phase 2** (or just always asset-encode the known blob fields and inline everything else — safest).

## 7. Record identity & system fields
- **recordName:** NSPCKC generates an opaque recordName per object (not the bare UUID). For **updates**, we must reuse the existing record's recordName + `encodedSystemFields` (read during pull, persisted) and pass `savePolicy = .ifServerRecordUnchanged`. For **new** participant-created records, we generate a recordName — **🔎 VERIFY** what format NSPCKC uses so a participant-created record is accepted (likely any unique name works as long as the zone + type + fields are correct).
- **Zone:** shared records live in the share's custom zone `com.apple.coredata.cloudkit.share.<UUID>`, owned by the sharer. All participant pushes target **that** `CKRecordZone.ID` (owner's zone). **🔎 VERIFY** the exact zone name from a record's `recordID.zoneID`.

## 8. Deletes
A delete is a `CKModifyRecordsOperation` deletion of the record ID. Cascade is handled server-side by the `.deleteSelf` reference actions (Section 4), so deleting a `CD_Trip` should cascade its children — **🔎 VERIFY** by deleting a child vs. parent and observing.

---

## Open decisions feeding the plan
- If §4 shows references (expected) → push encoder builds `CKRecord.Reference(recordID:action:)` per relationship.
- If §7 shows recordName must match an NSPCKC-specific scheme for *new* records → we may need to mint records the owner will accept; confirm a participant-created record round-trips to the owner's NSPCKC without being rejected.
- If anything here is materially different from expected, **pause and reassess Path A** before writing the Phase 3 encoder.
