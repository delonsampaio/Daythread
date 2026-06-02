//
//  SettingsView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

private enum ReminderOffset: Int, CaseIterable, Identifiable {
    case fifteenMin = 15, thirtyMin = 30, oneHour = 60, oneDay = 1440
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fifteenMin: return "15 minutes before"
        case .thirtyMin:  return "30 minutes before"
        case .oneHour:    return "1 hour before"
        case .oneDay:     return "1 day before"
        }
    }
}

struct SettingsView: View {
    @AppStorage("daythread.userDisplayName") private var displayName = ""
    @AppStorage("daythread.calendarSyncEnabled") private var calendarSyncEnabled = true
    @AppStorage("daythread.notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("daythread.reminderMinutesBefore") private var reminderMinutes = 15

    var body: some View {
        List {
            Section {
                TextField("Your name", text: $displayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
            } header: {
                Text("Your Profile")
            } footer: {
                Text("Shown to people you share trips with, so they see who's who.")
            }

            Section {
                Toggle("Sync events to Apple Calendar", isOn: $calendarSyncEnabled)
            } header: {
                Text("Calendar")
            } footer: {
                Text("Adds events to a Daythread calendar in Apple Calendar. Individual events can be excluded from the event's edit screen.")
            }

            Section {
                Toggle("Event reminders", isOn: $notificationsEnabled)
                if notificationsEnabled {
                    Picker("Remind me", selection: $reminderMinutes) {
                        ForEach(ReminderOffset.allCases) { offset in
                            Text(offset.label).tag(offset.rawValue)
                        }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Daythread will send a reminder before each timed event. Applies to both in-app notifications and the Apple Calendar alarm.")
            }
            Section("Support") {
                NavigationLink("Help & FAQ") {
                    HelpView()
                }
            }
            Section("About") {
                Link("Privacy Policy", destination: URL(string: "https://daythread.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://daythread.app/terms")!)
                NavigationLink("Open-Source Licenses") {
                    Text("Licenses")
                        .navigationTitle("Licenses")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
