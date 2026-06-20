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
    /// The timezone the picker displays and interprets times in.
    /// Pass the transit's departure or arrival timezone for transit events so
    /// "10:30 AM" is stored as 10:30 AM in THAT timezone, not the device timezone.
    var timeZone: TimeZone = .current

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode           = .time
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval           = minuteInterval
        picker.timeZone                 = timeZone
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.dateChanged(_:)),
                         for: .valueChanged)
        // Resist both compression and expansion so SwiftUI respects the
        // picker's intrinsic button size and doesn't squish it.
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.timeZone = timeZone
        // Snap the bound date to the nearest interval so the wheel always
        // shows a valid tick mark even if the value arrived from elsewhere.
        let snapped = snap(selection, to: minuteInterval)
        if abs(uiView.date.timeIntervalSince(snapped)) > 1 {
            uiView.date = snapped
        }
    }

    /// Report the compact picker's intrinsic button size so SwiftUI allocates
    /// exactly that width. Without this the picker is handed the parent's
    /// proposed width (often too narrow after a Spacer), and UIKit horizontally
    /// compresses the "12:25 PM" label — the squished-digits bug.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        let fitting = uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: fitting.width, height: fitting.height)
    }

    // MARK: — Coordinator

    final class Coordinator: NSObject {
        var parent: MinuteIntervalTimePicker
        init(_ parent: MinuteIntervalTimePicker) { self.parent = parent }

        @objc func dateChanged(_ sender: UIDatePicker) {
            // Snap to the interval so the bound value carries zero seconds.
            // UIDatePicker enforces the minute interval visually but still
            // reports the live seconds component, which would make two
            // boundary-adjacent events (e.g. 10–11pm and 11pm–12am) appear to
            // overlap by a few seconds in ScheduleEngine.
            parent.selection = parent.snap(sender.date, to: parent.minuteInterval)
        }
    }

    // MARK: — Helpers

    /// Rounds `date` to the nearest `interval` minutes, interpreted in `timeZone`.
    private func snap(_ date: Date, to interval: Int) -> Date {
        guard interval > 0 else { return date }
        var cal = Calendar.current
        cal.timeZone = timeZone
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let m      = c.minute ?? 0
        let ticks  = Int((Double(m) / Double(interval)).rounded())
        let capped = ticks * interval
        c.minute   = capped % 60
        c.second   = 0
        if capped >= 60 { c.hour = (c.hour ?? 0) + 1 }
        return cal.date(from: c) ?? date
    }
}
