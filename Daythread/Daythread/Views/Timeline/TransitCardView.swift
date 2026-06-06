//
//  TransitCardView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import CoreData

struct TransitCardView: View {
    let event: TripEvent
    let details: TransitDetails

    private var departureTZ: TimeZone {
        TimeZone(identifier: details.departureTZIdentifier) ?? .current
    }
    private var arrivalTZ: TimeZone {
        TimeZone(identifier: details.arrivalTZIdentifier) ?? .current
    }
    private var isOvernight: Bool {
        guard let depart = event.startTime, let arrive = event.endTime else { return false }
        return TimezoneEngine.overnightArrival(depart: depart, arrive: arrive,
                                               fromTZ: departureTZ, toTZ: arrivalTZ)
    }

    var body: some View {
        LiveContent(isDead: !event.isAlive || !details.isAlive) {
        VStack(alignment: .leading, spacing: 10) {
            // Carrier + flight number
            HStack {
                Text(details.carrier)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text(details.flightOrTrainNumber)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ThemeTokens.textSecondary)
                Spacer()
                if event.isPrivate && event.day?.trip?.cloudKitShareID != nil {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ThemeTokens.textMuted)
                }
                if event.isTimeLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ThemeTokens.warningAmber)
                }
                Image(systemName: event.category.systemImage)
                    .foregroundStyle(event.category.accentColor)
            }

            // Route: departure → arrival
            // Flights use large IATA codes; other transport promotes the station/stop
            // name to the primary display since departureCode/arrivalCode are empty.
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if details.departureCode.isEmpty {
                        Text(details.departureName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(ThemeTokens.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(details.departureCode)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(ThemeTokens.textPrimary)
                    }
                    if let time = event.startTime {
                        Text(TimezoneEngine.displayTime(date: time, in: departureTZ))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    if !details.departureCode.isEmpty, !details.departureName.isEmpty {
                        Text(details.departureName)
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(ThemeTokens.textMuted)
                    if let depart = event.startTime, let arrive = event.endTime {
                        Text(TimezoneEngine.durationString(seconds: arrive.timeIntervalSince(depart)))
                            .font(.caption2)
                            .foregroundStyle(ThemeTokens.textMuted)
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if details.arrivalCode.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            if isOvernight {
                                Text("+1")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ThemeTokens.warningAmber)
                                    .padding(.top, 4)
                            }
                            Text(details.arrivalName)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(ThemeTokens.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 4) {
                            Text(details.arrivalCode)
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundStyle(ThemeTokens.textPrimary)
                            if isOvernight {
                                Text("+1")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ThemeTokens.warningAmber)
                                    .baselineOffset(16)
                            }
                        }
                    }
                    if let time = event.endTime {
                        Text(TimezoneEngine.displayTime(date: time, in: arrivalTZ))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    if !details.arrivalCode.isEmpty, !details.arrivalName.isEmpty {
                        Text(details.arrivalName)
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            // Terminal / Gate / PNR chips
            FlowLayout(spacing: 6) {
                if let terminal = details.departureTerminal, !terminal.isEmpty {
                    transitChip("\(terminalLabel) \(terminal)", color: ThemeTokens.textSecondary)
                }
                if let gate = details.departureGate, !gate.isEmpty {
                    transitChip("Gate \(gate)", color: ThemeTokens.textSecondary)
                }
                if let carriage = details.carriageNumber, !carriage.isEmpty {
                    transitChip("Coach \(carriage)", color: ThemeTokens.textSecondary)
                }
                if let seat = details.seatNumber, !seat.isEmpty {
                    transitChip(seat, color: ThemeTokens.textSecondary)
                }
                if let plate = details.vehicleLicensePlate, !plate.isEmpty {
                    transitChip(plate, color: ThemeTokens.textSecondary)
                }
                if !details.pnr.isEmpty {
                    Text(details.pnr)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ThemeTokens.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ThemeTokens.accent.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(ThemeTokens.accent.opacity(0.3), lineWidth: 1))
                        )
                }
            }
        }
        .padding(14)
        .background(ThemeTokens.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ThemeTokens.cardCornerRadius))
        .cardShadow()
        }
    }

    private var terminalLabel: String {
        switch event.category {
        case .train: return "Platform"
        case .bus:   return "Bay"
        default:     return "Terminal"
        }
    }

    @ViewBuilder
    private func transitChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(ThemeTokens.backgroundPrimary)
                    .overlay(Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 0.5))
            )
    }
}

/// Simple flow layout for chip wrapping.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for subview in row.subviews {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var subviews: [LayoutSubview] = []; var height: CGFloat = 0 }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !rows[rows.count - 1].subviews.isEmpty {
                rows.append(Row())
                x = 0
            }
            rows[rows.count - 1].subviews.append(subview)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}
