//
//  SettingsView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("daythread.userDisplayName") private var displayName = ""

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
