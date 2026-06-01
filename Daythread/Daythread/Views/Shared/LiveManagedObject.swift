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
import CoreData

extension NSManagedObject {
    /// False once the object is dead: either deleted-but-not-yet-saved
    /// (`isDeleted`) OR deleted-and-saved, which invalidates the object and
    /// drops its `managedObjectContext` to nil while `isDeleted` flips back to
    /// false. Reading a non-optional @NSManaged value type on a dead object
    /// returns nil and traps in _unconditionallyBridgeFromObjectiveC, so views
    /// observing managed objects must gate their body on this.
    var isAlive: Bool {
        !isDeleted && managedObjectContext != nil
    }
}

struct LiveContent<Content: View>: View {
    let isDead: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isDead {
            // Nothing to show — the parent list/section is about to drop this row.
            Color.clear.frame(width: 0, height: 0)
        } else {
            content()
        }
    }
}
