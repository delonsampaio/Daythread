# Daythread

**Trip & Itinerary Builder** — native iOS app for friend groups tired of planning trips through iMessage chaos.

- **iOS 26+** · SwiftUI · SwiftData + CloudKit · Liquid Glass
- **$9.99 one-time Lifetime Pro IAP** (StoreKit 2, non-consumable, Family Sharing on)
- **Architecture:** Pragmatic B — `@Query` reads in views · ViewModels own writes + derived state · Engine layer (pure structs, zero UIKit/SwiftUI)

## Features

**Free:** Multi-day timeline · Drag-and-drop reorder · Transit cards (PNR, gate, terminal) · Global lodging header · Pre-trip checklist · Document vault (5 docs) · Apple Calendar sync · iCloud backup

**Pro ($9.99):** Real-time co-editing · ETA visualization · Expense splitting · Group polling · Live flight tracking · Dynamic Island · Home screen widgets

## Tech Stack

- Swift 6 · SwiftUI · iOS 26+
- SwiftData + CloudKit (iCloud containers)
- Observation framework (`@Observable`)
- StoreKit 2
- XCTest / Swift Testing
