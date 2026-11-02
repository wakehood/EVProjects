//
//  AdaptiveSemicircleSOCStyle.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 7/21/26.
//

import SwiftUI

struct AdaptiveSemicircleSoCStyle: GaugeStyle {
    var valueFontSize: CGFloat = 44

    private let startAngle = Angle(degrees: 180)
    private let endAngle = Angle(degrees: 360)
    
    func makeBody(configuration: Configuration) -> some View {
        // Enforce a tiny baseline layout number so the arc vectors don't collapse to 0 width
        let percentage = configuration.value > 0 ? configuration.value : 0.001
        
        return ZStack {
            // 1. Structural Track Base
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: GaugeMetrics.gaugeStrokeWidth, lineCap: .round))
            
            // 2. Active Gradient Fill Color Path
            Circle()
                .trim(from: 0.5, to: 0.5 + (0.5 * percentage))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .red,    // Critical (<10%)
                            .orange, // Low
                            .yellow, // Medium
                            .green   // Full (100%)
                        ]),
                        center: .center,
                        startAngle: startAngle,
                        endAngle: endAngle
                    ),
                    style: StrokeStyle(lineWidth: GaugeMetrics.gaugeStrokeWidth, lineCap: .round)
                )
                .shadow(color: .green.opacity(percentage > 0.5 ? 0.15 : 0.0), radius: 8)
            
            // 3. Central Elements text alignment grid
            VStack(spacing: 0) {
                configuration.currentValueLabel
                    .font(.system(size: valueFontSize, weight: .black, design: .monospaced))
                    .foregroundColor(.primary)

                configuration.label
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(2.0)
            }
            .offset(y: 25)

            // 4. Endpoint Tick Marks
            HStack {
                Capsule()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 2, height: 8)
                Spacer()
                Capsule()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 2, height: 8)
            }
            .offset(y: 11)

            // 5. Boundary Numbers – positioned below the arc endpoints
            HStack {
                Text("0%")
                    .offset(x: -8)
                Spacer()
                Text("100%")
                    .offset(x: 8)
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.secondary)
            .offset(y: 26)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
