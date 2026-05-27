//
//  SettingsView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
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
