//
//  SwipeRevealCard.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/29/26.
//
//  Wraps an event card with swipe-left-to-reveal actions (Edit · Lock · Delete).
//
//  Design notes:
//  • simultaneousGesture lets horizontal swipes be caught here while vertical
//    pans still propagate to the enclosing ScrollView.
//  • The card slides left in a ZStack above the buttons; .clipped() confines
//    the animation to the card frame. The cardShadow (opacity 0.04, radius 8)
//    is imperceptibly trimmed during a swipe — the trade-off is worth the
//    clean layout.
//  • The left-column time/icon in TimelineItem sits outside this view in the
//    parent HStack and is unaffected by the swipe.
//  • Velocity check on gesture end (> 120 pt/s) prevents drag-and-drop finger
//    movement from accidentally opening the swipe panel.

import SwiftUI

struct SwipeRevealCard<Content: View>: View {
    let isLocked: Bool
    let editAction: () -> Void
    let lockAction: () -> Void
    let deleteAction: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var isOpen: Bool = false

    private let revealWidth: CGFloat = 216   // 3 buttons × 72 pt
    private let buttonWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            // Buttons are hidden at rest (opacity 0) to prevent them showing
            // through the card's rounded-corner gaps when not swiping.
            // They appear as soon as the swipe starts (offset < -8 pt).
            HStack(spacing: 0) {
                swipeButton(label: "Edit",
                            icon: "pencil",
                            color: Color(uiColor: .systemBlue),
                            action: editAction)
                swipeButton(label: isLocked ? "Unlock" : "Lock",
                            icon: isLocked ? "lock.open.fill" : "lock.fill",
                            color: Color(uiColor: .systemOrange),
                            action: lockAction)
                swipeButton(label: "Delete",
                            icon: "trash",
                            color: Color(uiColor: .systemRed),
                            action: deleteAction)
            }
            .frame(width: revealWidth)
            .opacity(offset < -8 ? 1 : 0)

            // Card: slides left, covering then revealing the buttons.
            // Tap on the card while open → close the panel.
            content
                .offset(x: offset)
                .onTapGesture { if isOpen { close() } }
        }
        .clipped()
        .simultaneousGesture(swipeGesture)
    }

    // MARK: — Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                // Ignore vertical-dominant gestures (propagate to ScrollView)
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = isOpen ? -revealWidth : 0
                let proposed = base + value.translation.width
                offset = max(-revealWidth, min(0, proposed))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Low velocity = drag-and-drop motion, not a deliberate swipe — snap back.
                guard abs(value.velocity.width) > 120 else {
                    snap(to: isOpen ? -revealWidth : 0)
                    return
                }
                let shouldOpen = isOpen
                    ? value.velocity.width > 0 ? false : true   // fast rightward = close
                    : value.velocity.width < 0                   // fast leftward  = open
                snap(to: shouldOpen ? -revealWidth : 0)
                isOpen = shouldOpen
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

    private func swipeButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            // Close the panel first, then fire the action after the
            // spring animation settles so sheets open from a resting state.
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { action() }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            // Fixed width (centred) before the capsule so all pills are
            // the same size regardless of label length ("Edit" vs "Unlock").
            .frame(width: 56, alignment: .center)
            .padding(.vertical, 9)
            .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
        // Centre the pill within its 72 pt slot, vertically and horizontally.
        .frame(width: buttonWidth, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
