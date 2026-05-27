//
//  TransitDetails.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  CloudKit compliance: inline property defaults on all non-optional stored properties.
//

import Foundation
import SwiftData

@Model
final class TransitDetails {
    var id: UUID = UUID()
    var carrier: String = ""
    var flightOrTrainNumber: String = ""
    var pnr: String = ""
    var departureCode: String = ""       // IATA airport or station code — "CDG"
    var arrivalCode: String = ""
    var departureName: String = ""
    var arrivalName: String = ""
    var departureTerminal: String?
    var arrivalTerminal: String?
    var departureGate: String?
    var arrivalGate: String?
    var seatNumber: String?
    var baggageClaim: String?
    var departureTZIdentifier: String = "UTC"   // TimeZone.identifier — "Europe/Paris"
    var arrivalTZIdentifier: String = "UTC"

    var event: TripEvent?

    init(
        id: UUID = UUID(),
        carrier: String = "",
        flightOrTrainNumber: String = "",
        pnr: String = "",
        departureCode: String = "",
        arrivalCode: String = "",
        departureName: String = "",
        arrivalName: String = "",
        departureTerminal: String? = nil,
        arrivalTerminal: String? = nil,
        departureGate: String? = nil,
        arrivalGate: String? = nil,
        seatNumber: String? = nil,
        baggageClaim: String? = nil,
        departureTZIdentifier: String = TimeZone.current.identifier,
        arrivalTZIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.carrier = carrier
        self.flightOrTrainNumber = flightOrTrainNumber
        self.pnr = pnr
        self.departureCode = departureCode
        self.arrivalCode = arrivalCode
        self.departureName = departureName
        self.arrivalName = arrivalName
        self.departureTerminal = departureTerminal
        self.arrivalTerminal = arrivalTerminal
        self.departureGate = departureGate
        self.arrivalGate = arrivalGate
        self.seatNumber = seatNumber
        self.baggageClaim = baggageClaim
        self.departureTZIdentifier = departureTZIdentifier
        self.arrivalTZIdentifier = arrivalTZIdentifier
    }
}
