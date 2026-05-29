# Daythread — Backlog

Items are ordered by value/effort ratio within each tier. Only items worth building are listed.

---

## v1.1

### watchOS Companion App (Pro)
Read-only watch app showing the active trip's current and next event, with a "Next Stop" complication powered by ETAEngine. Surfaces when the user's hands are full — luggage, crowded transit station, airport security. Natural Pro-tier add since it requires an active trip and ETA data.

**Scope:** New `DaythreadWatch` target · WatchConnectivity to mirror active TripDay · one complication family (corner or graphic circular) · no write operations.

---

### Expense Audit Trail
When settling up, users sometimes wonder "why do I owe this amount?" — especially on long trips with many expenses. A breakdown view accessible from each settlement row showing exactly which expenses contributed to the debt and each person's per-expense share. Increases trust in the splitter output and reduces "that doesn't look right" disputes.

**Scope:** Sheet presented from settlement row → grouped list of contributing `TripExpense` records → per-person share for each · read-only, no mutations.

---

### Multiple Payers per Expense
Some group bills are split across multiple cards at the point of sale (e.g. two people each pay half a restaurant bill). Today the model supports only one `paidByMemberID`. Supporting an array of (memberID, amountPaid) pairs would handle this without the workaround of logging two separate expenses.

**Scope:** Model change: replace `paidByMemberID: UUID?` with `payers: [(memberID: UUID, amount: Double)]` · update AddExpenseSheet · update ExpenseSplitter input mapping · migration of existing single-payer records.

---

### Time Conflict Detection & Resolution
When saving an event whose `startTime`–`endTime` window overlaps another timed event on the same day, show a non-blocking alert rather than silently saving. The alert names the conflicting event and offers three exits: re-open the time pickers to adjust, navigate to the conflicting event (save current, scroll-to and briefly highlight the target card), or save anyway. Only fires when both events have a `startTime` and an `endTime` — events with no times are ignored.

**Scope:** Conflict-check helper in `TimelineViewModel` (pure function, easy to unit-test) · non-blocking alert in `AddEditEventSheet` after the save path · scroll-to-and-highlight mechanism in `TimelineView` (ScrollViewProxy + `@State var highlightedEventID: UUID?` + brief amber animation on the target `TimelineItem`).

---

### Ride-Share Deep Linking
From a transit card in TransitCardView, one tap opens Uber or Lyft with the destination pre-filled. Solves standing-on-a-curb friction where the user already knows where they're going but has to context-switch apps to get there.

**Scope:** Deep link URL schemes for Uber (`uber://`) and Lyft (`lyft://`). Fall back to App Store if the app isn't installed. Add as an action button on transit cards that have an address.

---

## v1.2

### Maritime / Cruise Mode
Ships operate on "Ship Time" — a manually set timezone that may differ from the GPS coordinate timezone, and connectivity is often unavailable for days at a time. A toggle on TripDay that locks it to a specific manual timezone, decoupled from system/GPS timezone. Pair with bulk offline caching of that day's itinerary so the app works without a connection.

**Scope:** `TimezoneEngine` toggle: `locked(identifier: String)` vs `automatic` · TripDay property for locked timezone · offline-first fetch for locked days · UI indicator when Ship Time is active.

---

## Skipped (and why)

| Item | Reason skipped |
|------|---------------|
| Theme park sub-events | A general "confirmation code" field on any event covers the real need without dedicated categories |
| Granular POI tagging + map filtering | Depends on Custom Map Pins (Feature 84) not yet built; revisit when the map layer exists |
| HealthKit distance walked | Distance is already on the user's wrist; doesn't change any decision made in the app |
| Autonomous vehicle transit mode | Waymo operates in a handful of cities with no public deep link scheme; premature |
