//
//  CellVoltageRangeGaugeView.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 8/6/26.
//

import SwiftUI

/// Horizontal linear gauge showing cell voltage spread within the MCU cutoff range.
///
/// Gradient: red (low cutoff) → orange → yellow → green → blue → cyan → white (high cutoff).
/// A white outlined rectangle spans from cellMin to cellMax, marking the current spread.
struct CellVoltageRangeGaugeView: View {
    var cellMin: Double
    var cellMax: Double
    var lowCutoff: Double
    var highCutoff: Double

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isIPad: Bool { hSizeClass == .regular && vSizeClass == .regular }

    private func xFraction(_ voltage: Double) -> CGFloat {
        guard highCutoff > lowCutoff else { return 0 }
        let clamped = min(max(voltage, lowCutoff), highCutoff)
        return CGFloat((clamped - lowCutoff) / (highCutoff - lowCutoff))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            let labelH: CGFloat  = isIPad ? 16 : 12
            let spacer: CGFloat  = isIPad ? 6 : 4
            let cutoffH: CGFloat = isIPad ? 14 : 11
            let barH: CGFloat    = GaugeMetrics.gaugeStrokeWidth
            let barTop = labelH + spacer
            let needleInset: CGFloat = 3

            let minX = xFraction(cellMin) * w
            let maxX = xFraction(cellMax) * w

            ZStack(alignment: .topLeading) {

                // ── Gradient bar ──
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .cyan, .white],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w, height: barH)
                .clipShape(RoundedRectangle(cornerRadius: barH / 2))
                .position(x: w / 2, y: barTop + barH / 2)

                // ── White outlined rectangle from cellMin to cellMax ──
                Rectangle()
                    .fill(Color.white.opacity(0.70))
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
                    .frame(width: max(maxX - minX, 4), height: barH + needleInset * 2)
                    .position(x: (minX + maxX) / 2, y: barTop + barH / 2)

                // ── Min/max voltage labels above bar (collision-aware) ──
                let edgeGuard: CGFloat = isIPad ? 28 : 18
                let rawMinLX:  CGFloat = min(max(minX, edgeGuard), w - edgeGuard)
                let rawMaxLX:  CGFloat = min(max(maxX, edgeGuard), w - edgeGuard)
                let labelSepX: CGFloat = isIPad ? 72 : 44
                let labelMidX  = (rawMinLX + rawMaxLX) / 2
                let halfSepX   = max(abs(rawMaxLX - rawMinLX) / 2, labelSepX / 2)
                let adjMinLX   = min(max(labelMidX - halfSepX, edgeGuard), w - edgeGuard)
                // Ensure maxLX is always at least labelSepX to the right of minLX (handles equal-value case)
                let adjMaxLX   = min(max(labelMidX + halfSepX, adjMinLX + labelSepX), w - edgeGuard)

                Text(String(format: "%.3fV", cellMin))
                    .font(.system(size: isIPad ? 12 : 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .position(x: adjMinLX, y: labelH / 2)

                Text(String(format: "%.3fV", cellMax))
                    .font(.system(size: isIPad ? 12 : 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .position(x: adjMaxLX, y: labelH / 2)

                // ── Cutoff labels below bar ──
                Text(String(format: "%.2fV", lowCutoff))
                    .font(.system(size: isIPad ? 10 : 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.90))
                    .position(x: edgeGuard, y: barTop + barH + spacer + cutoffH / 2)

                Text(String(format: "%.2fV", highCutoff))
                    .font(.system(size: isIPad ? 10 : 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .position(x: w - edgeGuard, y: barTop + barH + spacer + cutoffH / 2)
            }
        }
    }
}

#Preview {
    ZStack {
        Color(white: 0.10)
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Normal").font(.caption2).foregroundStyle(.white)
                CellVoltageRangeGaugeView(
                    cellMin: 3.10, cellMax: 3.25,
                    lowCutoff: 2.40, highCutoff: 3.40
                )
                .frame(height: 60)
            }
            VStack(spacing: 4) {
                Text("Low").font(.caption2).foregroundStyle(.white)
                CellVoltageRangeGaugeView(
                    cellMin: 2.50, cellMax: 2.70,
                    lowCutoff: 2.40, highCutoff: 3.40
                )
                .frame(height: 60)
            }
            VStack(spacing: 4) {
                Text("High (near cutoff)").font(.caption2).foregroundStyle(.white)
                CellVoltageRangeGaugeView(
                    cellMin: 3.20, cellMax: 3.38,
                    lowCutoff: 2.40, highCutoff: 3.40
                )
                .frame(height: 60)
            }
        }
        .padding(24)
    }
}
