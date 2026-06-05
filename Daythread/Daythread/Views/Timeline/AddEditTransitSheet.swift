//
//  AddEditTransitSheet.swift
//  Daythread
//

import SwiftUI

struct AddEditTransitSheet: View {
    let details: TransitDetails
    let category: EventCategory
    @Environment(\.dismiss) private var dismiss

    // Shared fields
    @State private var carrier: String
    @State private var number: String
    @State private var pnr: String
    @State private var departureName: String
    @State private var arrivalName: String
    @State private var departureTZ: TimeZone
    @State private var arrivalTZ: TimeZone

    // Flight-only
    @State private var departureCode: String
    @State private var arrivalCode: String
    @State private var departureTerminal: String
    @State private var arrivalTerminal: String
    @State private var departureGate: String
    @State private var baggageClaim: String

    // Flight / train / bus
    @State private var seatNumber: String

    // Train-only (platform reuses departureTerminal; carriage is new field)
    @State private var departureTrack: String
    @State private var carriageNumber: String

    // Bus-only (bay reuses departureTerminal)
    @State private var departureBay: String

    // Ferry-only
    @State private var vehicleLicensePlate: String

    init(details: TransitDetails, category: EventCategory) {
        self.details = details
        self.category = category
        _carrier           = State(initialValue: details.carrier)
        _number            = State(initialValue: details.flightOrTrainNumber)
        _pnr               = State(initialValue: details.pnr)
        _departureName     = State(initialValue: details.departureName)
        _arrivalName       = State(initialValue: details.arrivalName)
        _departureTZ       = State(initialValue: TimeZone(identifier: details.departureTZIdentifier) ?? .current)
        _arrivalTZ         = State(initialValue: TimeZone(identifier: details.arrivalTZIdentifier) ?? .current)
        _departureCode     = State(initialValue: details.departureCode)
        _arrivalCode       = State(initialValue: details.arrivalCode)
        _departureTerminal = State(initialValue: details.departureTerminal ?? "")
        _arrivalTerminal   = State(initialValue: details.arrivalTerminal ?? "")
        _departureGate     = State(initialValue: details.departureGate ?? "")
        _baggageClaim      = State(initialValue: details.baggageClaim ?? "")
        _seatNumber        = State(initialValue: details.seatNumber ?? "")
        _departureTrack    = State(initialValue: details.departureTerminal ?? "")
        _carriageNumber    = State(initialValue: details.carriageNumber ?? "")
        _departureBay      = State(initialValue: details.departureTerminal ?? "")
        _vehicleLicensePlate = State(initialValue: details.vehicleLicensePlate ?? "")
    }

    // MARK: — Labels per type

    private var numberLabel: String {
        switch category {
        case .flight: return "Flight Number"
        case .train:  return "Train Number / Name"
        case .bus:    return "Route Number"
        default:      return "Number"
        }
    }

    private var numberPlaceholder: String {
        switch category {
        case .flight: return "e.g. AF447"
        case .train:  return "e.g. Acela 2150"
        case .bus:    return "e.g. 57B (optional)"
        default:      return ""
        }
    }

    private var pnrLabel: String {
        category == .flight ? "Confirmation #" : "Booking Ref"
    }

    private var departureLabel: String {
        switch category {
        case .flight: return "Departure Airport"
        case .train:  return "Departure Station"
        case .bus:    return "Departure Stop"
        case .ferry:  return "Departure Port"
        default:      return "Departure"
        }
    }

    private var arrivalLabel: String {
        switch category {
        case .flight: return "Arrival Airport"
        case .train:  return "Arrival Station"
        case .bus:    return "Arrival Stop"
        case .ferry:  return "Arrival Port"
        default:      return "Arrival"
        }
    }

    private var departurePlaceholder: String {
        switch category {
        case .flight: return "e.g. Charles de Gaulle"
        case .train:  return "e.g. London Euston"
        case .bus:    return "e.g. Victoria Coach Station"
        case .ferry:  return "e.g. Port of Dover"
        default:      return ""
        }
    }

    private var arrivalPlaceholder: String {
        switch category {
        case .flight: return "e.g. JFK"
        case .train:  return "e.g. Penn Station"
        case .bus:    return "e.g. Times Square Bus Terminal"
        case .ferry:  return "e.g. Calais Port"
        default:      return ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Header section (carrier + number + booking ref) ──────────
                Section(category.displayName) {
                    TextField("Carrier", text: $carrier)
                    if category != .ferry {
                        TextField(numberLabel, text: $number)
                            .font(category == .flight ? ThemeTokens.monoFont : .body)
                            .foregroundStyle(category == .bus && number.isEmpty
                                             ? ThemeTokens.textMuted : ThemeTokens.textPrimary)
                    }
                    TextField(pnrLabel, text: $pnr)
                        .font(ThemeTokens.monoFont)
                        .textInputAutocapitalization(.characters)
                }

                // ── Departure ────────────────────────────────────────────────
                Section(departureLabel) {
                    if category == .flight {
                        TextField("IATA Code (e.g. CDG)", text: $departureCode)
                            .font(ThemeTokens.monoFont)
                            .textInputAutocapitalization(.characters)
                    }
                    TextField(departurePlaceholder, text: $departureName)
                    if category == .flight {
                        TextField("Terminal", text: $departureTerminal)
                        TextField("Gate", text: $departureGate)
                    }
                    if category == .train {
                        TextField("Platform / Track", text: $departureTrack)
                    }
                    if category == .bus {
                        TextField("Bay / Stand (optional)", text: $departureBay)
                    }
                    TimeZonePicker(label: "Time Zone", selected: $departureTZ)
                }

                // ── Arrival ──────────────────────────────────────────────────
                Section(arrivalLabel) {
                    if category == .flight {
                        TextField("IATA Code (e.g. JFK)", text: $arrivalCode)
                            .font(ThemeTokens.monoFont)
                            .textInputAutocapitalization(.characters)
                    }
                    TextField(arrivalPlaceholder, text: $arrivalName)
                    if category == .flight {
                        TextField("Terminal", text: $arrivalTerminal)
                        TextField("Baggage Claim", text: $baggageClaim)
                    }
                    TimeZonePicker(label: "Time Zone", selected: $arrivalTZ)
                }

                // ── Seat / Cabin ─────────────────────────────────────────────
                switch category {
                case .flight, .train, .bus:
                    Section(category == .train ? "Seat" : "Seat") {
                        if category == .train {
                            TextField("Carriage / Car", text: $carriageNumber)
                                .font(ThemeTokens.monoFont)
                        }
                        TextField("Seat Number (optional)", text: $seatNumber)
                            .font(ThemeTokens.monoFont)
                    }
                case .ferry:
                    Section("Cabin") {
                        TextField("Cabin / Berth (optional)", text: $seatNumber)
                            .font(ThemeTokens.monoFont)
                        TextField("Vehicle Reg (optional)", text: $vehicleLicensePlate)
                            .font(ThemeTokens.monoFont)
                            .textInputAutocapitalization(.characters)
                    }
                default:
                    EmptyView()
                }
            }
            .navigationTitle("\(category.displayName) Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        details.carrier              = carrier
        details.flightOrTrainNumber  = number
        details.pnr                  = pnr
        details.departureName        = departureName
        details.arrivalName          = arrivalName
        details.departureTZIdentifier = departureTZ.identifier
        details.arrivalTZIdentifier   = arrivalTZ.identifier

        switch category {
        case .flight:
            details.departureCode     = departureCode
            details.arrivalCode       = arrivalCode
            details.departureTerminal = departureTerminal.isEmpty ? nil : departureTerminal
            details.arrivalTerminal   = arrivalTerminal.isEmpty ? nil : arrivalTerminal
            details.departureGate     = departureGate.isEmpty ? nil : departureGate
            details.arrivalGate       = nil
            details.baggageClaim      = baggageClaim.isEmpty ? nil : baggageClaim
            details.seatNumber        = seatNumber.isEmpty ? nil : seatNumber
            details.carriageNumber    = nil
            details.vehicleLicensePlate = nil
        case .train:
            details.departureCode     = ""
            details.arrivalCode       = ""
            details.departureTerminal = departureTrack.isEmpty ? nil : departureTrack
            details.arrivalTerminal   = nil
            details.departureGate     = nil
            details.arrivalGate       = nil
            details.baggageClaim      = nil
            details.seatNumber        = seatNumber.isEmpty ? nil : seatNumber
            details.carriageNumber    = carriageNumber.isEmpty ? nil : carriageNumber
            details.vehicleLicensePlate = nil
        case .bus:
            details.departureCode     = ""
            details.arrivalCode       = ""
            details.departureTerminal = departureBay.isEmpty ? nil : departureBay
            details.arrivalTerminal   = nil
            details.departureGate     = nil
            details.arrivalGate       = nil
            details.baggageClaim      = nil
            details.seatNumber        = seatNumber.isEmpty ? nil : seatNumber
            details.carriageNumber    = nil
            details.vehicleLicensePlate = nil
        case .ferry:
            details.departureCode     = ""
            details.arrivalCode       = ""
            details.departureTerminal = nil
            details.arrivalTerminal   = nil
            details.departureGate     = nil
            details.arrivalGate       = nil
            details.baggageClaim      = nil
            details.seatNumber        = seatNumber.isEmpty ? nil : seatNumber
            details.carriageNumber    = nil
            details.vehicleLicensePlate = vehicleLicensePlate.isEmpty ? nil : vehicleLicensePlate
        default:
            break
        }
    }
}

struct TimeZonePicker: View {
    let label: String
    @Binding var selected: TimeZone
    @State private var showPicker = false

    private var displayName: String {
        selected.identifier
            .components(separatedBy: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? selected.identifier
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(displayName).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                TimeZoneSearchView(selected: $selected)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showPicker = false }.fontWeight(.semibold)
                        }
                    }
            }
        }
    }
}

private struct TimeZoneSearchView: View {
    @Binding var selected: TimeZone
    @State private var allIDs: [String] = []
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [String] {
        guard !query.isEmpty else { return allIDs }
        let q = query.lowercased()
        return allIDs.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        List(filtered, id: \.self) { id in
            Button {
                selected = TimeZone(identifier: id) ?? .current
                dismiss()
            } label: {
                HStack {
                    Text(id.replacingOccurrences(of: "_", with: " "))
                        .foregroundStyle(.primary)
                    Spacer()
                    if id == selected.identifier {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ThemeTokens.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $query, prompt: "Search time zones")
        .navigationTitle("Time Zone")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { allIDs = TimeZone.knownTimeZoneIdentifiers }
    }
}
