//
//  AddEditTransitSheet.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct AddEditTransitSheet: View {
    let details: TransitDetails
    @Environment(\.dismiss) private var dismiss

    @State private var carrier: String = ""
    @State private var flightNumber: String = ""
    @State private var pnr: String = ""
    @State private var departureCode: String = ""
    @State private var arrivalCode: String = ""
    @State private var departureName: String = ""
    @State private var arrivalName: String = ""
    @State private var departureTerminal: String = ""
    @State private var arrivalTerminal: String = ""
    @State private var departureGate: String = ""
    @State private var arrivalGate: String = ""
    @State private var seatNumber: String = ""
    @State private var baggageClaim: String = ""
    @State private var departureTZ: TimeZone = .current
    @State private var arrivalTZ: TimeZone = .current

    var body: some View {
        NavigationStack {
            Form {
                Section("Flight / Train") {
                    TextField("Carrier (e.g. Air France)", text: $carrier)
                    TextField("Number (e.g. AF447)", text: $flightNumber)
                        .font(ThemeTokens.monoFont)
                    TextField("Confirmation #", text: $pnr)
                        .font(ThemeTokens.monoFont)
                        .textInputAutocapitalization(.characters)
                }
                Section("Departure") {
                    TextField("Airport Code (e.g. CDG)", text: $departureCode)
                        .font(ThemeTokens.monoFont)
                        .textInputAutocapitalization(.characters)
                    TextField("Airport / Station name", text: $departureName)
                    TextField("Terminal", text: $departureTerminal)
                    TextField("Gate", text: $departureGate)
                    TimeZonePicker(label: "Time Zone", selected: $departureTZ)
                }
                Section("Arrival") {
                    TextField("Airport Code (e.g. JFK)", text: $arrivalCode)
                        .font(ThemeTokens.monoFont)
                        .textInputAutocapitalization(.characters)
                    TextField("Airport / Station name", text: $arrivalName)
                    TextField("Terminal", text: $arrivalTerminal)
                    TextField("Baggage Claim", text: $baggageClaim)
                    TimeZonePicker(label: "Time Zone", selected: $arrivalTZ)
                }
                Section("Seat") {
                    TextField("Seat (e.g. 24A)", text: $seatNumber)
                        .font(ThemeTokens.monoFont)
                }
            }
            .navigationTitle("Transit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { populate() }
    }

    private func populate() {
        carrier = details.carrier; flightNumber = details.flightOrTrainNumber
        pnr = details.pnr; departureCode = details.departureCode
        arrivalCode = details.arrivalCode; departureName = details.departureName
        arrivalName = details.arrivalName
        departureTerminal = details.departureTerminal ?? ""
        arrivalTerminal = details.arrivalTerminal ?? ""
        departureGate = details.departureGate ?? ""
        arrivalGate = details.arrivalGate ?? ""
        seatNumber = details.seatNumber ?? ""
        baggageClaim = details.baggageClaim ?? ""
        departureTZ = TimeZone(identifier: details.departureTZIdentifier) ?? .current
        arrivalTZ = TimeZone(identifier: details.arrivalTZIdentifier) ?? .current
    }

    private func save() {
        details.carrier = carrier; details.flightOrTrainNumber = flightNumber
        details.pnr = pnr; details.departureCode = departureCode
        details.arrivalCode = arrivalCode; details.departureName = departureName
        details.arrivalName = arrivalName
        details.departureTerminal = departureTerminal.isEmpty ? nil : departureTerminal
        details.arrivalTerminal = arrivalTerminal.isEmpty ? nil : arrivalTerminal
        details.departureGate = departureGate.isEmpty ? nil : departureGate
        details.arrivalGate = arrivalGate.isEmpty ? nil : arrivalGate
        details.seatNumber = seatNumber.isEmpty ? nil : seatNumber
        details.baggageClaim = baggageClaim.isEmpty ? nil : baggageClaim
        details.departureTZIdentifier = departureTZ.identifier
        details.arrivalTZIdentifier = arrivalTZ.identifier
    }
}

/// Simple timezone picker backed by TimeZone.knownTimeZoneIdentifiers
struct TimeZonePicker: View {
    let label: String
    @Binding var selected: TimeZone

    var body: some View {
        Picker(label, selection: $selected) {
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { id in
                Text(id).tag(TimeZone(identifier: id) ?? TimeZone.current)
            }
        }
    }
}
