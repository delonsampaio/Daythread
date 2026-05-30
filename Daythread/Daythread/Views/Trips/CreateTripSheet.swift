//
//  CreateTripSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData
import PhotosUI

struct CreateTripSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var vm = TripsViewModel()
    @State private var step: Int = 1

    // Step 1
    @State private var name: String = ""
    @State private var destination: String = ""
    // Step 2
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    // Step 3
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 1: stepOne
                case 2: stepTwo
                case 3: stepThree
                default: EmptyView()
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == 1 { Button("Cancel") { dismiss() } }
                    else { Button("Back") { step -= 1 } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if step < 3 {
                        Button("Next") { step += 1 }
                            .fontWeight(.semibold)
                            .disabled(step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Create") { createTrip() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var stepOne: some View {
        Form {
            Section("Step 1 of 3 — Basic Info") {
                TextField("Trip name (e.g. Paris in June)", text: $name)
                TextField("Destination", text: $destination)
            }
        }
    }

    private var stepTwo: some View {
        Form {
            Section("Step 2 of 3 — Dates") {
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
        }
        // Guard: if the user moves startDate past endDate, snap endDate forward.
        // Without this, the end DatePicker silently clamps to startDate but the
        // stored @State value stays stale, creating a zero-length trip.
        .onChange(of: startDate) { _, newStart in
            if endDate < newStart {
                endDate = newStart
            }
        }
    }

    private var stepThree: some View {
        Form {
            Section("Step 3 of 3 — Cover Photo (optional)") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.fill")
                        .foregroundStyle(ThemeTokens.accent)
                }
                if let data = coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                coverImageData = try? await item?.loadTransferable(type: Data.self)
            }
        }
    }

    private func createTrip() {
        let trip = vm.createTrip(
            name: name,
            destination: destination.isEmpty ? name : destination,
            start: startDate,
            end: endDate,
            context: context
        )
        trip.coverImageData = coverImageData
        try? context.save()
        store.activeTrip = trip
        HapticManager.shared.sheetConfirm()
        dismiss()
    }
}
