# Time Conflict Detection — Implementation Plan

> **Status:** Ready to implement (post Gemini review + decisions applied)
> **TDD rule:** Every test must fail before any production code is written.

---

## Final Decisions

| Topic | Decision |
|---|---|
| Where the logic lives | New `ScheduleEngine` struct (pure, static) — NOT in VM |
| Overlap rule | Strict `<` — adjacent events touching at a boundary are NOT conflicts |
| Alert options | Two only: **"Adjust Time"** (cancel, stay in form) + **"Save Anyway"** (save + dismiss) |
| "Go to event" option | **Dropped** — wiring cost too high, not needed |
| `TimelineItem` highlight | **Dropped** — no navigation = no highlight needed |
| `highlightedEventID` state | **Dropped** |
| `ScrollViewReader` | **Dropped** |
| Highlight clear pattern | **Dropped** (no highlight feature) |
| Midnight-spanning concern | **Rejected** — DatePicker uses `.hourAndMinute`, endTime < startTime returns [] |
| Day scoping | Check `day.events` only (live object, not a snapshot) |
| Drag-and-drop | No conflict check — existing lock-order validation is sufficient |
| Linear scan | Correct — no optimisation needed |
| Reduce motion | Skip pulse animation if `accessibilityReduceMotion` is true |
| VoiceOver on alert | Alert text already read aloud — no extra announcement needed |
| CloudKit | Pass live `day.events` at save time, not a captured snapshot |

---

## Engine Design

**New file:** `Daythread/Engines/ScheduleEngine.swift`

```swift
struct ScheduleEngine {
    /// Returns all events in `candidates` whose time window strictly overlaps [startTime, endTime).
    /// - Adjacent events touching at a single point are NOT conflicts.
    /// - Returns [] if startTime >= endTime (degenerate/inverted window).
    /// - Skips candidates that lack either startTime or endTime.
    /// - Excludes the event identified by `excludingID` (the event being edited).
    static func findConflicts(
        startTime: Date,
        endTime: Date,
        among candidates: [TripEvent],
        excludingID: UUID? = nil
    ) -> [TripEvent]
}
```

**Overlap condition:** `startTime < candidate.endTime && candidate.startTime < endTime`

---

## Files Changed

| File | Change |
|---|---|
| `Engines/ScheduleEngine.swift` | **New** — pure conflict detection |
| `AddEditEventSheet.swift` | Intercept save → check conflicts → alert if any |
| `ConflictDetectionTests.swift` | **New** — 27 unit tests (TDD, written first) |
| No changes to | `TimelineViewModel`, `TimelineItem`, `TimelineView`, `TimelineView` |

---

## Alert Wiring (AddEditEventSheet)

```
Save tapped
└── checkAndSave()
    ├── guard hasStartTime else → save() as normal
    ├── guard endTime > startTime else → save() as normal
    ├── conflicts = ScheduleEngine.findConflicts(
    │       startTime: startTime,
    │       endTime: endTime,
    │       among: selectedDay?.events ?? [],
    │       excludingID: editingEvent?.id
    │   )
    ├── conflicts.isEmpty → save() as normal
    └── conflicts not empty →
            pendingConflicts = conflicts
            showConflictAlert = true

Alert body: names all conflicting events + their time windows
Alert buttons:
  "Adjust Time"  → dismisses alert only (user stays in form)
  "Save Anyway"  → save() then dismiss sheet
```

New state on `AddEditEventSheet`:
- `@State private var showConflictAlert: Bool = false`
- `@State private var pendingConflicts: [TripEvent] = []`

---

## All 27 Tests (ConflictDetectionTests.swift)

### Group 1 — Overlap geometry (9 tests)
```
testConflictPartialOverlapBStartsDuringA
    A(8–10am), B(9–11am) → [B]

testConflictPartialOverlapAStartsDuringB
    A(9–11am), B(8–10am) → [B]

testConflictAFullyContainsB
    A(8am–12pm), B(9–10am) → [B]

testConflictBFullyContainsA
    A(9–10am), B(8am–12pm) → [B]

testConflictIdenticalWindows
    A(8–10am), B(8–10am) → [B]

testNoConflictAdjacentBStartsAtAEnd
    A(8–10am), B(10am–12pm) → []

testNoConflictAdjacentAStartsAtBEnd
    A(10am–12pm), B(8–10am) → []

testNoConflictGapBetweenABeforeB
    A(8–9am), B(10–11am) → []

testNoConflictGapBetweenBBeforeA
    A(10–11am), B(8–9am) → []
```

### Group 2 — Missing time fields (7 tests)
```
testNoConflictWhenCheckingWindowHasNilStartTime
    call site guards this — engine takes non-optional Date, returns []
    (test via AddEditEventSheet: hasStartTime=false → no check called)

testNoConflictWhenCheckingWindowEndBeforeStart
    startTime=10am, endTime=8am → []   (degenerate window guard)

testNoConflictWhenCheckingWindowEndEqualsStart
    startTime=8am, endTime=8am → []   (zero-duration guard)

testNoConflictWhenCandidateHasNilStartTime
    A(8–10am), B(nil start, 11am end) → []

testNoConflictWhenCandidateHasNilEndTime
    A(8–10am), B(9am start, nil end) → []

testNoConflictWhenCandidateIsFullyUntimed
    A(8–10am), B(nil, nil) → []

testNoConflictWhenAllCandidatesAreUntimed
    A(8–10am), candidates=[B(nil,nil), C(nil,nil)] → []
```

### Group 3 — Self-exclusion (2 tests)
```
testExcludesEditingEventFromConflictResults
    candidates=[A(8–10am)], excludingID=A.id → []

testEditingEventNotSelfReportedWhenOtherConflictExists
    candidates=[A(8–10am), B(9–11am)], excludingID=A.id → [B]
```

### Group 4 — Multiple conflicts (2 tests)
```
testReturnsAllConflictingEventsNotJustFirst
    A(8am–12pm), candidates=[B(9–10am), C(10:30–11am)] → [B, C]

testReturnsThreeConflicts
    A(8am–12pm), candidates=[B(9–10am), C(10:30–11am), D(11:30am–12pm)] → [B, C, D]
```

### Group 5 — Empty / no candidates (2 tests)
```
testNoConflictWhenCandidatesListIsEmpty
    A(8–10am), candidates=[] → []

testNoConflictWhenNoCandidatesOverlap
    A(8–9am), candidates=[B(10–11am), C(12–1pm)] → []
```

### Group 6 — Locked events (2 tests)
```
testConflictDetectedAgainstLockedEvent
    B.isTimeLocked=true, A(8–10am) overlaps B(9–11am) → [B]

testLockStatusDoesNotAffectConflictDetection
    A.isTimeLocked=true, A(8–10am) overlaps B(9–11am) → [B]
```

### Group 7 — Category irrelevance (1 test)
```
testConflictDetectedForTransitCategoryEvent
    B.category=.transit, A(8–10am) overlaps B(9–11am) → [B]
```

### Group 8 — Degenerate / edge (2 tests)
```
testNoConflictWhenEndTimeBeforeStartTime
    startTime=10am, endTime=8am → []

testNoConflictWhenEndTimeEqualsStartTime
    startTime=8am, endTime=8am → []
```

---

## TDD Order

1. Write ALL 27 tests → run → confirm all fail with "findConflicts not found"
2. Add `ScheduleEngine.swift` with the struct and empty func returning `[]`
3. Run → confirm all 27 fail with wrong result (not compile error)
4. Implement the function body
5. Run → confirm all 27 pass
6. Wire `AddEditEventSheet`: add state vars + `checkAndSave()` + `.alert` modifier
7. Manual QA: add event with overlapping times → see alert → test both buttons
8. Commit

---

## Alert Copy

**Title:** `"Time Conflict"`

**Body (1 conflict):**
`"[Event Title] ([start]–[end]) overlaps on the same day."`

**Body (2 conflicts):**
`"[Event A] and [Event B] overlap on the same day."`

**Body (3+ conflicts):**
`"[Event A], [Event B], and [N] others overlap on the same day."`

**Buttons:**
- `"Adjust Time"` — role: `.cancel`
- `"Save Anyway"` — role: `.destructive`
