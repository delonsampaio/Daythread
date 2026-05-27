//
//  AddEditLodgingSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct AddEditLodgingSheet: View {
    let trip: Trip
    var editingLodging: LodgingInfo? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var checkIn: Date = Date()
    @State private var checkOut: Date = Date().addingTimeInterval(86400)
    @State private var confirmationNumber: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Property") {
                    TextField("Hotel / Rental name", text: $name)
                    TextField("Address", text: $address)
                }
                Section("Stay") {
                    DatePicker("Check-in", selection: $checkIn, displayedComponents: .date)
                    DatePicker("Check-out", selection: $checkOut, displayedComponents: .date)
                }
                Section("Booking") {
                    TextField("Confirmation number", text: $confirmationNumber)
                        .font(ThemeTokens.monoFont)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(editingLodging == nil ? "Add Lodging" : "Edit Lodging")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let l = editingLodging {
                name = l.name; address = l.address; checkIn = l.checkIn
                checkOut = l.checkOut; confirmationNumber = l.confirmationNumber; notes = l.notes
            }
        }
    }

    private func save() {
        if let lodging = editingLodging {
            lodging.name = name; lodging.address = address; lodging.checkIn = checkIn
            lodging.checkOut = checkOut; lodging.confirmationNumber = confirmationNumber
            lodging.notes = notes
        } else {
            let lodging = LodgingInfo(name: name, address: address,
                                      checkIn: checkIn, checkOut: checkOut,
                                      confirmationNumber: confirmationNumber, notes: notes)
            lodging.trip = trip
            context.insert(lodging)
        }
        try? context.save()
        HapticManager.shared.sheetConfirm()
    }
}
