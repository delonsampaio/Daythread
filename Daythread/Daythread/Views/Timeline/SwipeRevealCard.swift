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
//    Delete = red. Color is the only affordance on icon-only circles, especially
//    in dark mode, so each action keeps a distinct semantic colour.
//  • openID binding — shared across the whole timeline. Opening this card sets
//    openID = self.id; any other open card observes the change and closes itself,
//    so at most one panel is visible at a time.
//  • simultaneousGesture lets horizontal swipes be caught here while vertical
//    pans still propagate to the enclosing ScrollView.
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
            // Action circles — hidden at rest so they don't bleed through
            // the card's rounded-corner gaps; appear as soon as swipe starts.
            HStack(spacing: 0) {
                circleButton(label: "Edit",
                             icon: "pencil",
                             color: Color(uiColor: .systemBlue),
                             action: editAction)
                // Orange matches the amber lock icon already used on locked cards.
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

            // Card slides left; tap it while open to close the panel.
            content
                .offset(x: offset)
                .onTapGesture { if isOpen { close() } }
        }
        .clipped()
        .simultaneousGesture(swipeGesture)
        // Close when another card's panel opens.
        .onChange(of: openID) { _, newID in
            if newID != id, isOpen { close() }
        }
    }

    // MARK: — Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = isOpen ? -revealWidth : 0
                offset = max(-revealWidth, min(0, base + value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard abs(value.velocity.width) > 120 else {
                    snap(to: isOpen ? -revealWidth : 0)
                    return
                }
                let shouldOpen = isOpen ? value.velocity.width < 0 : value.velocity.width < 0
                if shouldOpen { openID = id }   // signal other cards to close
                isOpen = shouldOpen
                snap(to: shouldOpen ? -revealWidth : 0)
            }
    }

    // MARK: — Helpers

    private func snap(to targetOffset: CGFloat) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            offset = targetOffset
        }
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
