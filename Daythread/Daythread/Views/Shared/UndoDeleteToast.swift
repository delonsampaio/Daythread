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
    /// Drains 1 → 0 over `duration` to show remaining undo time.
    @State private var barProgress: CGFloat = 1

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
                // Restart the countdown bar: snap full, then drain over `duration`.
                barProgress = 1
                withAnimation(.linear(duration: duration)) { barProgress = 0 }
                let item = DispatchWorkItem {
                    onCommit(p.id)
                    pending = nil
                }
                workItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
            }
    }

    private func toast(for p: PendingDelete) -> some View {
        VStack(spacing: 10) {
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
            // Countdown bar draining left-to-right over the undo window.
            Capsule()
                .fill(.white.opacity(0.55))
                .frame(height: 3)
                .scaleEffect(x: barProgress, anchor: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.darkText).opacity(0.9))
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
