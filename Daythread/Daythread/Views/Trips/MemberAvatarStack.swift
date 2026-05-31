//
//  MemberAvatarStack.swift
//  Daythread
//
//  Overlapping avatar circles shown on TripCardView to signal "group trip"
//  at a glance. Shows up to 3 member avatars; overflow is shown as "+N".
//
//  Uses HStack(spacing: -overlap) for correct SwiftUI layout — ZStack+offset
//  does not affect layout bounds and caused circles to clip off-screen.
//

import SwiftUI

struct MemberAvatarStack: View {
    let members: [TripMember]

    private let size: CGFloat = 26
    private let overlap: CGFloat = 8
    private let maxVisible = 3

    private var visible: [TripMember] { Array(members.prefix(maxVisible)) }
    private var overflow: Int { max(0, members.count - maxVisible) }

    var body: some View {
        HStack(spacing: -overlap) {
            // First member renders on top (highest zIndex), last on bottom.
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                avatar(for: member)
                    .zIndex(Double(visible.count - index))
            }
            if overflow > 0 {
                overflowBadge
                    .zIndex(0)
            }
        }
    }

    @ViewBuilder
    private func avatar(for member: TripMember) -> some View {
        Circle()
            .strokeBorder(.black.opacity(0.25), lineWidth: 1.5)
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
            .fill(Color.black.opacity(0.4))
            .strokeBorder(.black.opacity(0.25), lineWidth: 1.5)
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
