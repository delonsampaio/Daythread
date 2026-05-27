//
//  EventCategory.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation

enum EventCategory: String, Codable, CaseIterable {
    // Transit
    case flight, train, bus, ferry
    // Accommodation
    case hotel, rentalProperty
    // Food & drink
    case restaurant, cafe, bar
    // Culture & entertainment
    case museum, attraction, tour, show
    // Active
    case activity, sport, hike
    // Other
    case shopping, other

    nonisolated var displayName: String {
        switch self {
        case .flight:          return "Flight"
        case .train:           return "Train"
        case .bus:             return "Bus"
        case .ferry:           return "Ferry"
        case .hotel:           return "Hotel"
        case .rentalProperty:  return "Rental"
        case .restaurant:      return "Restaurant"
        case .cafe:            return "Café"
        case .bar:             return "Bar"
        case .museum:          return "Museum"
        case .attraction:      return "Attraction"
        case .tour:            return "Tour"
        case .show:            return "Show"
        case .activity:        return "Activity"
        case .sport:           return "Sport"
        case .hike:            return "Hike"
        case .shopping:        return "Shopping"
        case .other:           return "Other"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .flight:          return "airplane"
        case .train:           return "tram.fill"
        case .bus:             return "bus.fill"
        case .ferry:           return "ferry.fill"
        case .hotel:           return "bed.double.fill"
        case .rentalProperty:  return "house.fill"
        case .restaurant:      return "fork.knife"
        case .cafe:            return "cup.and.saucer.fill"
        case .bar:             return "wineglass.fill"
        case .museum:          return "building.columns.fill"
        case .attraction:      return "star.fill"
        case .tour:            return "map.fill"
        case .show:            return "theatermasks.fill"
        case .activity:        return "figure.walk"
        case .sport:           return "sportscourt.fill"
        case .hike:            return "mountain.2.fill"
        case .shopping:        return "bag.fill"
        case .other:           return "ellipsis.circle.fill"
        }
    }

    nonisolated var isTransit: Bool {
        [.flight, .train, .bus, .ferry].contains(self)
    }

    nonisolated var requiresTransitDetails: Bool { isTransit }
}

// MARK: — SwiftUI (MainActor — views only)
import SwiftUI

@MainActor
extension EventCategory {
    var accentColor: Color {
        switch self {
        case .flight, .train, .bus, .ferry:    return .blue
        case .hotel, .rentalProperty:          return .indigo
        case .restaurant, .cafe, .bar:         return .orange
        case .museum, .attraction, .tour, .show: return .purple
        case .activity, .sport, .hike:         return .green
        case .shopping, .other:                return .gray
        }
    }
}
