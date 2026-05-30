//
//  MinuteIntervalTimePicker.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/29/26.
//
//  SwiftUI's DatePicker does not expose a minute interval parameter.
//  This UIViewRepresentable wraps UIDatePicker with minuteInterval = 5,
//  producing the same compact-button appearance as DatePicker but only
//  allowing 0, 5, 10, … 55 on the minute wheel.
//

import SwiftUI
import UIKit

struct MinuteIntervalTimePicker: UIViewRepresentable {
    let label: String
    @Binding var selection: Date
    var minuteInterval: Int = 5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode           = .time
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval           = minuteInterval
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.dateChanged(_:)),
                         for: .valueChanged)
        // Resist both compression and expansion so SwiftUI respects the
        // picker's intrinsic button size and doesn't squish it.
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    /// Tells SwiftUI the picker's preferred size so it doesn't guess wrong.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker,
                      context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        // Snap the bound date to the nearest interval so the wheel always
        // shows a valid tick mark even if the value arrived from elsewhere.
        let snapped = snap(selection, to: minuteInterval)
        if abs(uiView.date.timeIntervalSince(snapped)) > 1 {
            uiView.date = snapped
        }
    }

    // MARK: — Coordinator

    final class Coordinator: NSObject {
        var parent: MinuteIntervalTimePicker
        init(_ parent: MinuteIntervalTimePicker) { self.parent = parent }

        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }

    // MARK: — Helpers

    /// Rounds `date` to the nearest `interval` minutes.
    private func snap(_ date: Date, to interval: Int) -> Date {
        guard interval > 0 else { return date }
        var c = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let m      = c.minute ?? 0
        let ticks  = Int((Double(m) / Double(interval)).rounded())
        let capped = ticks * interval
        c.minute   = capped % 60
        c.second   = 0
        if capped >= 60 { c.hour = (c.hour ?? 0) + 1 }
        return Calendar.current.date(from: c) ?? date
    }
}
