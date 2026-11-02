//
//  MotorSpeedGaugeView.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 7/15/26.
//

import SwiftUI

// MARK: - Semicircle Motor Speed Gauge Style
struct SemicircleMotorSpeedGaugeStyle: GaugeStyle {
    var valueFontSize: CGFloat = 44

    private let startAngle = Angle(degrees: 180)
    private let endAngle = Angle(degrees: 360)

    func makeBody(configuration: Configuration) -> some View {
        let percentage = configuration.value

        return ZStack {
            // 1. Semi-Transparent Background Scale Track
            Circle()
                .trim(from: startAngle.degrees / 360, to: endAngle.degrees / 360)
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: GaugeMetrics.gaugeStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(0))

            // 2. Active RPM Arc + Redline Glow
            Circle()
                .trim(from: startAngle.degrees / 360, to: angleRange(for: percentage) / 360)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .cyan,    // Low RPM
                            .green,   // Moderate RPM
                            .yellow,  // High RPM
                            .red      // Near Redline
                        ]),
                        center: .center,
                        startAngle: startAngle,
                        endAngle: endAngle
                    ),
                    style: StrokeStyle(lineWidth: GaugeMetrics.gaugeStrokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(0))
                .shadow(color: .red.opacity(percentage > 0.85 ? 0.3 : 0.0), radius: 8)

            // 3. Central RPM Readout
            VStack(spacing: 0) {
                configuration.currentValueLabel
                    .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                configuration.label
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(2.0)
            }
            .offset(y: 25)

            // 4. Static Axis Alignment Ticks
            HStack {
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 2, height: 8)
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 2, height: 8)
            }
            .offset(y: 11)

            // 5. Static Boundary Endpoint Labels (0 to 18K)
            HStack {
                Text("0")
                    .offset(x: -8)
                Spacer()
                Text("18K")
                    .offset(x: 8)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.8))
            .offset(y: 26)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func angleRange(for percentage: Double) -> Double {
        let sweep = endAngle.degrees - startAngle.degrees
        return startAngle.degrees + (sweep * percentage)
    }
}

