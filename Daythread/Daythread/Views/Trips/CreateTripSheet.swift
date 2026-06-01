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

    @State private var name: String = ""
    @State private var destination: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Trip name (e.g. Paris in June)", text: $name)
                    TextField("Destination", text: $destination)
                }

                Section("Dates") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section("Cover Photo (optional)") {
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
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            // Guard: if the user moves startDate past endDate, snap endDate
            // forward. Without this the end DatePicker visually clamps but the
            // stored @State stays stale, creating a zero-length trip.
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart { endDate = newStart }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    coverImageData = try? await item?.loadTransferable(type: Data.self)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { createTrip() }
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
        }
        // Full-page on iPad (a small floating card looks awkward for a form);
        // a normal sheet on iPhone.
        .presentationSizing(.page)
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
