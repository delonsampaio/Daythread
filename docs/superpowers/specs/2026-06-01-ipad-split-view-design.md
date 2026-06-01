# iPad Split-View Navigation — Design

**Date:** 2026-06-01
**Status:** Approved for planning
**Target:** iOS/iPadOS 26.5 (deployment minimum; no availability checks needed)

## Goal

Give Daythread a proper iPad layout: on regular-width iPad the four top-level
sections (Timeline, Trips, Vault, Profile) appear in a **collapsible left
sidebar** with icons + labels, and the selected section fills a wide detail
pane. On iPhone (and compact-width iPad / Stage Manager), the existing Liquid
Glass bottom tab bar is preserved **exactly as-is**.

This replaces the current state where iPad shows the same iPhone-style bottom
tab bar (a stretched phone layout that wastes the iPad's width).

### Non-goals
- No sidebar trip list / master-detail of trips (that was Option A/C; we chose
  **Option B**: sidebar = the four tabs).
- No changes to iPhone layout or behavior.
- No changes to the four section views' internals.
- Deep-navigation preservation across size-class flips is **out of scope** for
  v1 (see Future Enhancements).

## Approach

Size-class-adaptive container. A new `RootView` reads
`horizontalSizeClass` and renders:
- `.compact` → `RootTabView` (the current `TabView` + `.tabItem`, iPhone)
- `.regular` → `RootSplitView` (a `NavigationSplitView`, iPad)

Rejected alternatives:
- `.tabViewStyle(.sidebarAdaptable)` — renders a collapsed **text-only top bar**
  by default (icons hidden until sidebar expanded). Verified on simulator
  2026-06-01; does not meet the icons-visible requirement.
- Always-`NavigationSplitView` — collapses to a navigation stack (not a tab bar)
  on compact width, so iPhone would lose its bottom bar. Rejected.

## Components

### `RootView` (new — app root)
Replaces `RootTabView()` as the root in `DaythreadApp`. Owns shared state and
lifecycle that must run once regardless of layout:
- `@State private var selectedTab: DaythreadTab = .timeline`
- `@FetchRequest` for `activeTrips` (moved up from `RootTabView`)
- `@State private var cloudKit = CloudKitService()` (moved up)
- `@Environment` `store` and `managedObjectContext`
- **All CloudKit sync observers** currently on `RootTabView` move here:
  `.onAppear` (initial tab + `selectInitialTripIfNeeded`), the three
  `.onChange` blocks (objectIDs participant sync, id-change pending-join +
  deleted-trip fallback, cloudKitShareID pending-join), and the
  `.onReceive(eventChangedNotification)` import handler.

Body:
```swift
Group {
    if horizontalSizeClass == .compact {
        RootTabView(selectedTab: $selectedTab)
    } else {
        RootSplitView(selectedTab: $selectedTab)
    }
}
// shared observers + onAppear attached here
```

### `RootTabView` (modified — iPhone UI only)
- Accepts `@Binding var selectedTab: DaythreadTab`.
- Keeps only the `TabView(selection:) { … .tabItem { Label(...) }.tag(...) }`
  body — unchanged visually.
- The `@FetchRequest`, `cloudKit` state, and all observer modifiers are
  **removed** (hoisted to `RootView`).

### `RootSplitView` (new — iPad UI)
- Accepts `@Binding var selectedTab: DaythreadTab`.
- `@State private var columnVisibility = NavigationSplitViewVisibility.all` so
  the sidebar is visible by default (even in portrait on 11" iPad) and still
  collapsible via the system toggle. Bound into the `NavigationSplitView`.
- Structure:
```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    List(selection: $selectedTab) {
        Label("Timeline", systemImage: ThemeTokens.tabTimeline).tag(DaythreadTab.timeline)
        Label("Trips",    systemImage: ThemeTokens.tabTrips).tag(DaythreadTab.trips)
        Label("Vault",    systemImage: ThemeTokens.tabVault).tag(DaythreadTab.vault)
        Label("Profile",  systemImage: ThemeTokens.tabProfile).tag(DaythreadTab.profile)
    }
    .navigationTitle("Daythread")
} detail: {
    switch selectedTab {
    case .timeline: TimelineView()
    case .trips:    TripsListView()
    case .vault:    VaultView()
    case .profile:  ProfileView()
    }
}
```

### The four section views — UNCHANGED
`TimelineView`, `TripsListView`, `VaultView`, `ProfileView` each already wrap
themselves in a `NavigationStack`. They render unchanged in both a tab and a
split-detail pane.

**Critical rule:** the split detail pane renders the selected view **directly,
with NO wrapping `NavigationStack`.** Each view's own internal stack serves the
detail column → exactly one stack, one nav bar, correct toolbar routing
(including the `.principal` trip-picker dropdown). Wrapping the detail in an
additional `NavigationStack` would nest two stacks and produce double nav bars —
this must be avoided.

## Data Flow
- `selectedTab` (`@State` in `RootView`, passed as `Binding`) drives both the
  `TabView` selection and the sidebar `List` selection. Shared, so a size-class
  flip preserves the active section.
- `store.activeTrip` remains the global trip selection (unchanged). Trip
  switching stays in the `.principal` nav-bar dropdown in each view — works in
  both a tab bar and a split detail pane.
- CloudKit observers fire once from `RootView` in both layouts.

## Edge Cases
1. **Runtime size-class flip** (rotation, Stage Manager resize, multitasking):
   `RootView` swaps children; `selectedTab` and `activeTrip` are hoisted/shared,
   so the user stays on the same section + trip. In-flight navigation pushes
   inside a view reset on the swap — standard SwiftUI, accepted for v1.
2. **First launch:** `.onAppear` sets `.timeline` and runs
   `selectInitialTripIfNeeded`, once, at `RootView`.
3. **Sidebar visibility:** `columnVisibility = .all` keeps the sidebar visible
   by default and collapsible.
4. **No active trip:** each view's existing empty state shows — unchanged.
5. **iPhone:** compact path is the current `TabView` verbatim — zero change.

## Testing / Verification
- Structural UI change, no new domain logic. The existing unit suite (~180
  tests) must remain green (build verification on iOS).
- Manual visual verification on both size classes:
  - **iPhone:** bottom Liquid Glass bar identical to current; all 4 tabs load;
    trip dropdown works.
  - **iPad (regular):** sidebar shows the 4 items with icons; collapsible;
    detail pane loads each section; trip dropdown works in the detail nav bar;
    CloudKit share/sync still functions.
  - **Stage Manager live-morph stress test:** open full-screen (regular →
    sidebar), drag the window down to a narrow iPhone-shaped floating window
    (compact → bottom bar) and back. `selectedTab` should persist and the app
    must not crash.

## Future Enhancements (backlog, not v1)
- **Deep-navigation preservation across size-class flips:** hoist a shared
  `NavigationPath` to `RootView` and pass it as a binding into the section
  views' `NavigationStack(path:)`, so a user deep inside e.g. a trip's detail
  isn't returned to the section root when the iPad rotates/resizes.
- Optional iPad-native master-detail of the trip list (the original Option A),
  if a future milestone wants the sidebar to surface trips rather than tabs.
