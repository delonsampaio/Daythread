//
//  LiveManagedObject.swift
//  Daythread
//
//  A render guard for views that @ObservedObject an NSManagedObject.
//
//  A deleted managed object returns nil for its non-optional @NSManaged value
//  types (UUID, Date, String). Reading one traps in
//  _unconditionallyBridgeFromObjectiveC. When an object is deleted — locally
//  (cascade delete) or via CloudKit sync (a co-editor losing access) — the
//  views observing it re-render for one pass over the dead object before
//  SwiftUI tears them down. This wrapper short-circuits that pass.
//
//  Usage: wrap the body content so the property-reading subtree is only built
//  while the object is alive:
//
//      var body: some View {
//          LiveContent(isDeleted: trip.isDeleted) {
//              VStack { Text(trip.name) ... }   // only evaluated when alive
//          }
//      }
//

import SwiftUI

struct LiveContent<Content: View>: View {
    let isDeleted: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isDeleted {
            // Nothing to show — the parent list/section is about to drop this row.
            Color.clear.frame(width: 0, height: 0)
        } else {
            content()
        }
    }
}
