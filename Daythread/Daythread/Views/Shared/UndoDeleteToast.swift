//
//  UndoDeleteToast.swift
//  Daythread
//
//  Reusable undo-on-delete pattern: an item is soft-hidden immediately,
//  a toast gives the user 4 seconds to undo, then the actual Core Data
//  delete fires. Trip-level deletes use a confirmation dialog instead.
//

import SwiftUI
import CoreData

// MARK: — State

/// Holds the pending deletion while the undo window is open.
struct PendingDelete: Equatable {
    let id: NSManagedObjectID
    let label: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: — ViewModifier

private struct UndoDeleteModifier: ViewModifier {
    @Binding var pending: PendingDelete?
    let duration: TimeInterval
    let onCommit: (NSManagedObjectID) -> Void

    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let p = pending {
                    toast(for: p)
                        .padding(.bottom, 100)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: pending)
            .onChange(of: pending) { _, newPending in
                workItem?.cancel()
                guard let p = newPending else { return }
                let item = DispatchWorkItem {
                    onCommit(p.id)
                    pending = nil
                }
                workItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
            }
    }

    private func toast(for p: PendingDelete) -> some View {
        HStack(spacing: 12) {
            Text("Deleted \u{201C}\(p.label)\u{201D}")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button("Undo") {
                workItem?.cancel()
                workItem = nil
                pending = nil
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.darkText).opacity(0.88))
        )
    }
}

// MARK: — View extension

extension View {
    /// Attaches the undo-delete toast to this view.
    ///
    /// - Parameters:
    ///   - pending: Binding to the in-flight deletion. Set it to a `PendingDelete`
    ///     to start the countdown; set it to `nil` (or tap Undo) to cancel.
    ///   - duration: Seconds before the deletion is committed. Default 4.
    ///   - onCommit: Called with the `NSManagedObjectID` when the timer fires.
    ///     Perform the actual `context.delete` + `context.save` here.
    func undoDelete(
        pending: Binding<PendingDelete?>,
        duration: TimeInterval = 4,
        onCommit: @escaping (NSManagedObjectID) -> Void
    ) -> some View {
        modifier(UndoDeleteModifier(pending: pending, duration: duration, onCommit: onCommit))
    }
}
