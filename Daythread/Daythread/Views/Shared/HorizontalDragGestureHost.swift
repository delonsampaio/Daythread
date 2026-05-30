//
//  HorizontalDragGestureHost.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/29/26.
//
//  A UIViewRepresentable that hosts a UIPanGestureRecognizer configured to
//  recognise ONLY horizontal pans.  Vertical pans fail immediately at the
//  UIKit layer (gestureRecognizerShouldBegin returns false), which lets the
//  enclosing UIScrollView claim those touches without any delay.
//
//  SwiftUI's DragGesture + simultaneousGesture can still block scroll because
//  the gesture enters its "changed" state (UIKit: .began) before any
//  directionality check runs.  A real UIPanGestureRecognizer can fail
//  BEFORE transitioning to .began, freeing the touch for UIScrollView.
//

import SwiftUI
import UIKit

struct HorizontalDragGestureHost: UIViewRepresentable {
    /// Called when the horizontal pan gesture begins (use to capture pre-gesture state).
    var onBegan: () -> Void = {}
    /// Translation.x (cumulative from gesture start, in points) as the pan progresses.
    var onChanged: (CGFloat) -> Void
    /// Final translation.x and velocity.x (pts/sec) when the gesture ends or cancels.
    var onEnded: (CGFloat, CGFloat) -> Void
    /// Fired when the user taps (no significant movement) — use to close the swipe panel.
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded, onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan   = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded   = onEnded
        context.coordinator.onTap     = onTap
    }

    // MARK: — Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan:   () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded:   (CGFloat, CGFloat) -> Void
        var onTap:     () -> Void

        init(
            onBegan:   @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded:   @escaping (CGFloat, CGFloat) -> Void,
            onTap:     @escaping () -> Void
        ) {
            self.onBegan   = onBegan
            self.onChanged = onChanged
            self.onEnded   = onEnded
            self.onTap     = onTap
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translationX = recognizer.translation(in: recognizer.view).x
            let velocityX    = recognizer.velocity(in: recognizer.view).x
            switch recognizer.state {
            case .began:    onBegan()
            case .changed:  onChanged(translationX)
            case .ended, .cancelled: onEnded(translationX, velocityX)
            default: break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { onTap() }
        }

        // MARK: UIGestureRecognizerDelegate

        /// Fail immediately for vertical pans.  Returning false here moves
        /// the recogniser to .failed BEFORE it reaches .began, so UIScrollView's
        /// pan recogniser is never prevented from starting.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let v = pan.velocity(in: view)
            // Require a clear horizontal intent (2:1 ratio) to start recognising.
            // Ambiguous or vertical gestures fail → ScrollView takes over.
            return abs(v.x) > abs(v.y) * 1.5
        }

        /// Allow simultaneous recognition with UIScrollView's pan so that when
        /// our recogniser fails (vertical swipe), the scroll view can immediately
        /// take the same touch sequence.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
