//
//  SwipeRevealCard.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/29/26.
//
//  Wraps an event card with swipe-left-to-reveal actions (Edit · Lock · Delete).
//
//  Design:
//  • Icon-only circles — no text labels, matching the native iOS swipe-action
//    aesthetic. accessibilityLabel provides text for VoiceOver.
//  • Edit = blue, Lock/Unlock = orange (mirrors the amber lock icon on cards),
//    Delete = red.
//  • openID binding — shared across the whole timeline. Opening this card sets
//    openID = self.id; any other open card observes the change and closes itself,
//    so at most one panel is visible at a time.
//  • HorizontalDragGestureHost replaces DragGesture + simultaneousGesture.
//    Using a real UIPanGestureRecognizer that fails for vertical swipes at the
//    UIKit level (gestureRecognizerShouldBegin) means the enclosing ScrollView
//    always gets vertical pans — scroll is never blocked.
//  • Velocity check (> 120 pt/s) prevents drag-and-drop motion from accidentally
//    opening the swipe panel after a long-press lift.

import SwiftUI

struct SwipeRevealCard<Content: View>: View {
    let id: UUID
    let isLocked: Bool
    let editAction: () -> Void
    let lockAction: () -> Void
    let deleteAction: () -> Void
    @Binding var openID: UUID?
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var isOpen: Bool = false
    /// Captures whether the panel was open at the START of the current gesture,
    /// so the base offset stays stable throughout the drag even if isOpen changes.
    @State private var gestureStartedOpen: Bool = false

    private let revealWidth: CGFloat = 216   // 3 slots × 72 pt
    private let buttonWidth: CGFloat = 72
    private let circleSize:  CGFloat = 46

    init(
        id: UUID,
        isLocked: Bool,
        editAction: @escaping () -> Void,
        lockAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void,
        openID: Binding<UUID?>,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.isLocked = isLocked
        self.editAction = editAction
        self.lockAction = lockAction
        self.deleteAction = deleteAction
        self._openID = openID
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Action circles — appear as soon as swipe starts.
            HStack(spacing: 0) {
                circleButton(label: "Edit",
                             icon: "pencil",
                             color: Color(uiColor: .systemBlue),
                             action: editAction)
                circleButton(label: isLocked ? "Unlock" : "Lock",
                             icon: isLocked ? "lock.open.fill" : "lock.fill",
                             color: Color(uiColor: .systemOrange),
                             action: lockAction)
                circleButton(label: "Delete",
                             icon: "trash",
                             color: Color(uiColor: .systemRed),
                             action: deleteAction)
            }
            .frame(width: revealWidth)
            .opacity(offset < -8 ? 1 : 0)

            // Card slides left; the gesture host is overlaid on the card so it
            // slides with it — action circles remain reachable when panel is open.
            content
                .offset(x: offset)
                .overlay {
                    HorizontalDragGestureHost(
                        onBegan:   { gestureStartedOpen = isOpen },
                        onChanged: { translationX in
                            let base: CGFloat = gestureStartedOpen ? -revealWidth : 0
                            offset = max(-revealWidth, min(0, base + translationX))
                        },
                        onEnded: { _, velocityX in
                            // Not enough velocity — snap back to current state.
                            guard abs(velocityX) > 120 else {
                                snap(to: gestureStartedOpen ? -revealWidth : 0)
                                return
                            }
                            let shouldOpen = velocityX < 0   // leftward = open
                            if shouldOpen { openID = id }    // signal other cards to close
                            isOpen = shouldOpen
                            snap(to: shouldOpen ? -revealWidth : 0)
                        },
                        onTap: { if isOpen { close() } }
                    )
                }
        }
        .clipped()
        // Close when another card's panel opens.
        .onChange(of: openID) { _, newID in
            if newID != id, isOpen { close() }
        }
    }

    // MARK: — Helpers

    private func snap(to targetOffset: CGFloat) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            offset = targetOffset
        }
        if targetOffset == 0 { isOpen = false }
        else { isOpen = true }
    }

    private func close() {
        isOpen = false
        snap(to: 0)
    }

    private func circleButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .frame(width: buttonWidth, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
