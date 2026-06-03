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
- **Booleans** are stored as **Int64 0/1**. **🔎 VERIFY.**
- Device-local attributes marked `syncable="NO"` (`ekEventIdentifier`, `hasReminder`, `showInCalendar`) are **NOT** present as CKRecord fields — do not write them. **🔎 VERIFY** they're absent.
- `CD_id` value matches the Core Data `id` UUID (used for our local upsert match). **🔎 VERIFY** the field name and that it carries the UUID.

## 3. Entity-name field
Each record carries a field **`CD_entityName`** = the Core Data entity name (e.g. `"TripEvent"`). **🔎 VERIFY present and exact key.**

## 4. To-one relationships (the critical part)
Stored as a CKRecord field `CD_<relationshipName>` whose value is a **`CKRecord.Reference`** to the related record, in the **same zone**.

- `CD_TripEvent.CD_day` → Reference to the `CD_TripDay` record.
- `CD_TripDay.CD_trip` → Reference to the `CD_Trip` record.
- `CD_TripEvent.CD_transitDetails` (inverse held on TransitDetails: `CD_TransitDetails.CD_event`).

**Reference action:** child→parent references that mirror a Core Data **Cascade** delete rule use **`CKReference.Action.deleteSelf`** (so deleting the parent record cascades). Nullify rules use `.none`.

**🔎 VERIFY (most important):** open a real `CD_TripEvent` record and confirm whether `CD_day` is a **Reference** (and its action) vs. a plain recordName string. This determines the entire push encoder.

## 5. To-many relationships
**Not stored on the parent.** Derived from the inverse to-one reference (Section 4). Our model's to-manys (Trip.days, TripDay.events, Trip.documents/expenses/lodging/members/preTripTasks) all have inverse to-ones, so **no `CDMR_*` companion records are expected.** **🔎 VERIFY** there are no `CDMR_*` record types in the schema.

## 6. Blobs → CKAsset
Binary attributes with `allowsExternalBinaryDataStorage=YES` are stored as **CKAsset** in field `CD_<attr>`:
`CD_coverImageData` (Trip), `CD_documentData` (TripDocument), `CD_receiptImageData` (TripExpense), `CD_avatarData` (TripMember). **🔎 VERIFY** they're CKAssets (not inline bytes).

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
