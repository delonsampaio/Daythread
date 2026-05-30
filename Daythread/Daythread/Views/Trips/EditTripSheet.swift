//
//  EditTripSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/28/26.
//
//  Full trip editor — name, destination, cover photo, and date range.
//  When the date range shrinks, vm.eventCountOutsideRange is consulted to
//  decide whether to surface a destructive-action warning before saving.
//  reconcileDays (inside vm.updateTrip) handles cascade deletion and re-indexing.
//

import SwiftUI
import CoreData
import PhotosUI

struct EditTripSheet: View {
    let trip: Trip
    let vm: TripsViewModel

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?
    @State private var showDestructiveAlert = false

    init(trip: Trip, vm: TripsViewModel) {
        self.trip = trip
        self.vm = vm
        _name        = State(initialValue: trip.name)
        _destination = State(initialValue: trip.destination)
        _startDate   = State(initialValue: trip.startDate)
        _endDate     = State(initialValue: trip.endDate)
        _coverImageData = State(initialValue: trip.coverImageData)
    }

    private var lostEventCount: Int {
        vm.eventCountOutsideRange(trip: trip, newStart: startDate, newEnd: endDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Info") {
                    TextField("Trip name", text: $name)
                    TextField("Destination", text: $destination)
                }

                Section("Dates") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                .onChange(of: startDate) { _, newStart in
                    if endDate < newStart { endDate = newStart }
                }

                Section("Cover Photo") {
                    let photoLabel = coverImageData == nil ? "Choose Photo" : "Change Photo"
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoLabel, systemImage: "photo.fill")
                            .foregroundStyle(ThemeTokens.accent)
                    }
                    if coverImageData != nil {
                        Button("Remove Photo", role: .destructive) {
                            coverImageData = nil
                            selectedPhoto = nil
                        }
                    }
                    if let data = coverImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task {
                        coverImageData = try? await item?.loadTransferable(type: Data.self)
                    }
                }
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { handleSave() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            // Shown only when shrinking the date range would delete events.
            .alert("Remove Events?", isPresented: $showDestructiveAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Remove \(lostEventCount) Event\(lostEventCount == 1 ? "" : "s")",
                       role: .destructive) {
                    saveTrip()
                }
            } message: {
                Text("\(lostEventCount) event\(lostEventCount == 1 ? "" : "s") will be permanently deleted because \(lostEventCount == 1 ? "it falls" : "they fall") outside the new date range.")
            }
        }
    }

    // MARK: — Actions

    private func handleSave() {
        if lostEventCount > 0 {
            showDestructiveAlert = true
        } else {
            saveTrip()
        }
    }

    private func saveTrip() {
        vm.updateTrip(
            trip,
            name: name.trimmingCharacters(in: .whitespaces),
            destination: destination.trimmingCharacters(in: .whitespaces),
            start: startDate,
            end: endDate,
            coverImageData: coverImageData,
            context: context
        )
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
