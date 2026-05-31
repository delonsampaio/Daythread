//
//  MemberAvatarStack.swift
//  Daythread
//
//  Overlapping avatar circles shown on TripCardView to signal "group trip"
//  at a glance. Shows up to 3 member avatars; overflow is shown as "+N".
//

import SwiftUI

struct MemberAvatarStack: View {
    let members: [TripMember]

    private let size: CGFloat = 26
    private let overlap: CGFloat = 8
    private let maxVisible = 3

    private var visible: [TripMember] {
        Array(members.prefix(maxVisible))
    }

    private var overflow: Int {
        max(0, members.count - maxVisible)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                    avatar(for: member)
                        .offset(x: CGFloat(index) * (size - overlap))
                        .zIndex(Double(visible.count - index))
                }
                if overflow > 0 {
                    overflowBadge
                        .offset(x: CGFloat(visible.count) * (size - overlap))
                        .zIndex(0)
                }
            }
            .frame(
                width: CGFloat(visible.count + (overflow > 0 ? 1 : 0)) * (size - overlap) + overlap,
                height: size
            )
        }
    }

    @ViewBuilder
    private func avatar(for member: TripMember) -> some View {
        Circle()
            .strokeBorder(.black.opacity(0.3), lineWidth: 1.5)
            .background(
                Group {
                    if let data = member.avatarData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle().fill(avatarColor(for: member))
                            .overlay(
                                Text(initials(for: member))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .clipShape(Circle())
            )
            .frame(width: size, height: size)
    }

    private var overflowBadge: some View {
        Circle()
            .fill(Color.black.opacity(0.45))
            .strokeBorder(.black.opacity(0.3), lineWidth: 1.5)
            .overlay(
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }

    private func initials(for member: TripMember) -> String {
        let parts = member.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        switch parts.count {
        case 0:  return "?"
        case 1:  return String(parts[0].prefix(2)).uppercased()
        default: return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
    }

    private func avatarColor(for member: TripMember) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .green]
        let index = abs(member.displayName.hashValue) % colors.count
        return colors[index]
    }
}
