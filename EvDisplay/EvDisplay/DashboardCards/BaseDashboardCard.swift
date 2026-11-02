//
//  BaseDashboardCard.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 7/20/26.
//

import SwiftUI

struct BaseDashboardCard<Content: View>: View {
    let title: String?
    let themeColor: Color
    let outlineOpacity: Double
    let outlineWidth: CGFloat
    let content: Content

    init(title: String? = nil, themeColor: Color, outlineOpacity: Double = 0.6, outlineWidth: CGFloat = 1.5, @ViewBuilder content: () -> Content) {
        self.title = title
        self.themeColor = themeColor
        self.outlineOpacity = outlineOpacity
        self.outlineWidth = outlineWidth
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeColor.opacity(outlineOpacity), lineWidth: outlineWidth)
                )

            VStack(alignment: .leading) {
                if let title {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(themeColor)
                        .padding([.top, .leading])
                }

                // Injects the card's specific UI
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
    }
}



