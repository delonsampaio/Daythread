//
//  ETAEngine.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  Pure Engine struct — no SwiftUI/SwiftData imports.
//  Protocol injection keeps it testable without a live network call.

import Foundation
import CoreLocation
import MapKit

// Protocol enables injection in tests — keeps Engine pure (no live network calls)
protocol DirectionsProviding: Sendable {
    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval
}

// Live implementation using MKDirections
struct MKDirectionsProvider: DirectionsProviding {
    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        let response = try await directions.calculateETA()
        return response.expectedTravelTime
    }
}

// Pure Engine struct — no MKDirections import needed in callers
struct ETAEngine {
    nonisolated static func eta(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        provider: any DirectionsProviding = MKDirectionsProvider()
    ) async throws -> TimeInterval {
        try await provider.calculateETA(from: origin, to: destination)
    }

    /// Human-readable format: "12m", "1h 30m", "2h"
    nonisolated static func formatETA(seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        case (let h, let m): return "\(h)h \(m)m"
        }
    }
}
