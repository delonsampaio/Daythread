//
//  HapticManager.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()
    private init() {}

    func dragLift() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    func dragDrop() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func lockToggle() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    func fabTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func swipeRevealOpen() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func swipeRevealClose() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func tabSwitch() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func sheetConfirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func deleteAction() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
