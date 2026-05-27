//
//  LodgingBannerView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI

struct LodgingBannerView: View {
    let lodging: LodgingInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 16))
                .foregroundStyle(ThemeTokens.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(lodging.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                if !lodging.address.isEmpty {
                    Text(lodging.address)
                        .font(.system(size: 12))
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "map.fill")
                .font(.system(size: 14))
                .foregroundStyle(ThemeTokens.accent)
                .onTapGesture { openInMaps(lodging) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect()
    }

    private func openInMaps(_ lodging: LodgingInfo) {
        let query = lodging.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(query)") {
            UIApplication.shared.open(url)
        }
    }
}
