//
//  TemperatureGaugeView.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 7/30/26.
//

import SwiftUI

// Single continuous thermometer path: rounded-top stem flows into bulb with no seams.
private struct ThermometerBody: Shape {
    func path(in rect: CGRect) -> Path {
        let cx      = rect.midX
        let stemW   = rect.width * 0.30
        let bulbR   = rect.width * 0.1875  // diameter = stemW × 1.25
        let halfSW  = stemW / 2
        let bulbCY  = rect.maxY - bulbR

        // Where the vertical stem sides are tangent to the bulb circle
        let tangentDY = sqrt(max(0, bulbR * bulbR - halfSW * halfSW))
        let tangentY  = bulbCY - tangentDY
        // Angle (degrees) of the tangent point measured from bulb centre
        let thetaDeg  = atan2(tangentDY, halfSW) * 180 / .pi

        var p = Path()
        // 1. Start at the right tangent point (stem meets bulb, right side)
        p.move(to: CGPoint(x: cx + halfSW, y: tangentY))
        // 2. Straight up the right side of the stem
        p.addLine(to: CGPoint(x: cx + halfSW, y: rect.minY + halfSW))
        // 3. Semicircular cap over the top
        //    clockwise:true in SwiftUI's Y-down coords = visually counterclockwise on screen,
        //    so the arc bows upward (over the top) as expected for a convex cap.
        p.addArc(center: CGPoint(x: cx, y: rect.minY + halfSW),
                 radius: halfSW,
                 startAngle: .degrees(0),
                 endAngle: .degrees(180),
                 clockwise: true)
        // 4. Straight down the left side of the stem
        p.addLine(to: CGPoint(x: cx - halfSW, y: tangentY))
        // 5. Bulb arc from left tangent around the bottom to right tangent (convex outward)
        p.addArc(center: CGPoint(x: cx, y: bulbCY),
                 radius: bulbR,
                 startAngle: .degrees(180 + thetaDeg),
                 endAngle: .degrees(-thetaDeg),
                 clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Vertical thermometer gauge showing two temperature readings.
///
/// - Range: -25 °C (bottom) to 100 °C (top)
/// - Blue  below 0 °C, Green 0–50 °C, Red above 50 °C
/// - White horizontal cursors mark each temperature value
struct TemperatureGaugeView: View {
    var temp1: Double
    var temp2: Double

    private let minTemp: Double = -25
    private let maxTemp: Double = 100

    // 0 = bottom (-25 °C), 1 = top (100 °C)
    private func fraction(for temp: Double) -> Double {
        (min(max(temp, minTemp), maxTemp) - minTemp) / (maxTemp - minTemp)
    }

    var body: some View {
        GeometryReader { geo in
            let w      = geo.size.width
            let h      = geo.size.height
            let stemW  = w * 0.30
            let bulbR  = w * 0.1875  // diameter = stemW × 1.25
            let cx     = w / 2
            let bulbCY = h - bulbR
            let stemBottom = bulbCY - sqrt(max(0, bulbR * bulbR - (stemW / 2) * (stemW / 2)))
            let stemH  = stemBottom   // stem top is y = 0

            // Fraction boundaries for color zones
            let f50 = CGFloat(fraction(for: 50))  // 0.600
            let f0  = CGFloat(fraction(for: 0))   // 0.200

            // Convert a temperature to a Y coordinate within the view
            let minT = minTemp, maxT = maxTemp
            let yFor = { (t: Double) -> CGFloat in
                let clamped = min(max(t, minT), maxT)
                let frac = (clamped - minT) / (maxT - minT)
                return stemBottom - stemH * CGFloat(frac)
            }

            ZStack(alignment: .topLeading) {

                // ── Color zone fill, clipped to thermometer silhouette ──
                VStack(spacing: 0) {
                    Rectangle().fill(Color.red)
                        .frame(height: stemH * (1 - f50))
                    Rectangle().fill(Color.green)
                        .frame(height: stemH * (f50 - f0))
                    Color.blue          // fills remaining stem + bulb area
                }
                .frame(width: w, height: h)
                .clipShape(ThermometerBody())

                // ── Thermometer outline ──
                ThermometerBody()
                    .stroke(Color.white.opacity(0.70), lineWidth: 2)

                // ── White rectangle spanning temp1 to temp2 ──
                let topY    = min(yFor(temp1), yFor(temp2))
                let bottomY = max(yFor(temp1), yFor(temp2))
                let rectH   = max(bottomY - topY, 4)
                Rectangle()
                    .fill(Color.white.opacity(0.70))
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
                    .frame(width: stemW + 10, height: rectH)
                    .position(x: cx, y: topY + rectH / 2)

                // Temperature labels (collision-aware)
                let rawY1:     CGFloat = yFor(temp1)
                let rawY2:     CGFloat = yFor(temp2)
                let labelSepY: CGFloat = 14   // min center-to-center distance (≈ label height)
                let labelMidY  = (rawY1 + rawY2) / 2
                let halfSepY   = max(abs(rawY1 - rawY2) / 2, labelSepY / 2)
                let adjY1 = rawY1 <= rawY2 ? labelMidY - halfSepY : labelMidY + halfSepY
                let adjY2 = rawY1 <= rawY2 ? labelMidY + halfSepY : labelMidY - halfSepY
                let labelX = cx + stemW / 2 + 22

                Text(String(format: "%.0f°C", temp1))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: labelX, y: adjY1)

                Text(String(format: "%.0f°C", temp2))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: labelX, y: adjY2)
            }
        }
    }
}

#Preview {
    ZStack {
        Color(white: 0.10)
        HStack(spacing: 16) {
            VStack {
                Text("Normal").font(.caption2).foregroundStyle(.white)
                TemperatureGaugeView(temp1: 22, temp2: 31)
                    .frame(width: 90, height: 220)
            }
            VStack {
                Text("Cold").font(.caption2).foregroundStyle(.white)
                TemperatureGaugeView(temp1: -10, temp2: 3)
                    .frame(width: 90, height: 220)
            }
            VStack {
                Text("Hot").font(.caption2).foregroundStyle(.white)
                TemperatureGaugeView(temp1: 58, temp2: 72)
                    .frame(width: 90, height: 220)
            }
        }
        .padding(24)
    }
}
