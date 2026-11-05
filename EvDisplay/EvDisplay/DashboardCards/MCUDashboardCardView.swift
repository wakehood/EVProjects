//
//  MCUDashboardCardView.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 8/2/26.
//

import SwiftUI
import OBD2Kit

struct MCUDashboardCardView: View {
    @Environment(OBD2ConnectionManager.self) private var manager: OBD2ConnectionManager
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var showingHealth = false
    @State private var showingFirmwareAlert = false
    @State private var showingInfo = false
    @State private var longPressJustFired = false

    // iPad has regular in both axes; iPhone Pro Max landscape is regular/compact
    private var isIPad: Bool { hSizeClass == .regular && vSizeClass == .regular }

    private var infoButton: some View {
        Image(systemName: "info.circle")
            .font(.system(size: isIPad ? 20 : 16))
            .foregroundColor(.secondary)
            .onTapGesture {
                guard !longPressJustFired else { longPressJustFired = false; return }
                showingInfo = true
            }
            .onLongPressGesture(minimumDuration: 3.0) {
                longPressJustFired = true
                manager.activateDemoMode()
            }
    }

    private let scaleThresholds: [Double] = [0, 2, 5, 10, 20, 50, 100, 200, 500]

    private var anyAlert: Bool {
        manager.alertGroundFault == 1 || manager.alertHardware == 1 ||
        manager.alertCCensus == 1    || manager.alertTCensus == 1   ||
        manager.alertHVC == 1        || manager.alertLVC == 1       ||
        manager.alertHiTemp == 1     || manager.alertLoTemp == 1    ||
        manager.alertNotLocked == 1  || manager.alertIllegalConf == 1
    }

    var body: some View {
        let powerKW = (manager.rawPackVoltage * manager.rawPackCurrent) / 1000.0
        let isCharging = powerKW >= 0
        let powerColor: Color = isCharging ? Color("Primary Green") : .red
        let normalizedPower = calculateLogProgress(for: abs(powerKW))

        BaseDashboardCard(themeColor: Color("Deep Contrast Teal"), outlineOpacity: 0.9, outlineWidth: 2.0) {
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    landscapeLayout(geo: geo, powerKW: powerKW, isCharging: isCharging,
                                    powerColor: powerColor, normalizedPower: normalizedPower)
                } else {
                    portraitLayout(geo: geo, powerKW: powerKW, isCharging: isCharging,
                                   powerColor: powerColor, normalizedPower: normalizedPower)
                }
            }
            .padding(8)
        }
        .sheet(isPresented: $showingHealth) {
            HealthDashboardCardView()
                .environment(manager)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingInfo) {
            AppInfoSheet(manager: manager)
                .presentationDetents([.medium])
        }
        .alert("Firmware Update Recommended", isPresented: $showingFirmwareAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("MCU firmware \(manager.mcuVersion) is below the recommended version \(MCUConstants.minimumFirmwareString). The app will work but some fields, such as available energy, may not display. Please update the MCU firmware for the best experience.")
        }
        .onChange(of: manager.hasReceivedStatus) { _, received in
            if received && manager.firmwareTooOld {
                showingFirmwareAlert = true
            }
        }
    }

    // MARK: - Landscape
    //
    // Two rows:
    //   Top (expands):  Left = SOC + kWh  |  Right = Power (top) / Temp (bottom)
    //   Bottom (fixed): Left = Status + Alert  |  Right = Cells gauge
    @ViewBuilder
    private func landscapeLayout(
        geo: GeometryProxy,
        powerKW: Double,
        isCharging: Bool,
        powerColor: Color,
        normalizedPower: Double
    ) -> some View {
        let bottomH:  CGFloat = isIPad ? 130 : 80
        let topH      = geo.size.height - bottomH
        let gaugeSize = min(geo.size.width * 0.42, topH * 0.80,
                            isIPad ? GaugeMetrics.socGaugeMaxIPad : GaugeMetrics.socGaugeMaxPhone)
        let barHeight = min(topH * 0.78, isIPad ? 460.0 : 120.0)
        let tempH     = min(topH * 0.82, isIPad ? 340.0 : 90.0)
        let tempW: CGFloat = isIPad ? 72.0 : 40.0

        VStack(spacing: 0) {

            // ── Top row ──
            HStack(alignment: .top, spacing: 0) {

                // Left half: SOC gauge + available energy
                VStack(spacing: 0) {
                    Text("Energy")
                        .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                    Text(String(format: "%.1f kWh", manager.rawAvailableEnergyKwh))
                        .font(.system(size: isIPad ? 26 : 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)
                    Spacer(minLength: 0)
                    Gauge(value: Double(manager.rawSOCPercentage), in: 0...100) {
                        Text("Charge")
                    } currentValueLabel: {
                        Text("\(manager.rawSOCPercentage)%")
                    }
                    .gaugeStyle(AdaptiveSemicircleSoCStyle(valueFontSize: isIPad ? 64 : 44))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.rawSOCPercentage)
                    .frame(width: gaugeSize, height: gaugeSize)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Right half: Power (left) | Temperature (right)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        
                        // Power sub-section: bar + kW (top), Pack V / Current (bottom)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Power")
                                .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            Spacer(minLength: 0)
                            HStack(alignment: .center, spacing: 12) {
                                PowerBarView(
                                    normalizedPower: normalizedPower,
                                    powerColor: powerColor,
                                    thresholds: scaleThresholds,
                                    barHeight: barHeight,
                                    barWidth: isIPad ? 22 : 16
                                )
                                Text(String(format: "%.2f kW", abs(powerKW)))
                                    .font(.system(size: isIPad ? 28 : 20, design: .monospaced))
                                    .fontWeight(.black)
                                    .foregroundColor(powerColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                             Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()

                        // Temperature sub-section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Temp")
                                .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer(minLength: 0)
                            TemperatureGaugeView(temp1: manager.rawMcuLowTemp, temp2: manager.rawMcuHighTemp)
                                .frame(width: tempW, height: tempH)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .padding(.vertical, 6)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pack")
                            .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                      
                        HStack(spacing: 12) {
                            Text(String(format: "%.1fV", manager.rawPackVoltage))
                            Text(String(format: "%.1fA", manager.rawPackCurrent))
                        }
                        .font(.system(size: isIPad ? 28 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                        .padding(.top, 4)
                        .padding(.bottom, isIPad ? 20 : 10)
                     
                        
                    }
                    .padding(.top, 4)
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // ── Bottom row (fixed height) ──
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                // Left half: connection status + alert button
                    HStack(alignment: .center, spacing: 16) {
                        Text(manager.connectionStatus)
                            .font(.system(size: isIPad ? 16 : 12, weight: .semibold, design: .rounded))
                            .foregroundColor(
                                manager.isConnected ? Color("Primary Green") :
                                    manager.connectionStatus == String(localized: "Bluetooth Off") ? .red : .orange
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.leading, 20)
                        
                        Spacer()

                        if manager.hasReceivedStatus {
                            Button {
                                showingHealth = true
                            } label: {
                                Image(systemName: anyAlert ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                    .font(.system(size: isIPad ? 36 : 24, weight: .semibold))
                                    .foregroundColor(anyAlert ? .red : Color("Primary Green"))
                            }
                            .buttonStyle(.plain)
                        }
                        if manager.scanTimedOut {
                            Button {
                                manager.retryScanning()
                            } label: {
                                Text("Retry")
                                    .font(.system(size: isIPad ? 16 : 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                        infoButton
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                // Right half: cell voltage range
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cells")
                        .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    CellVoltageRangeGaugeView(
                        cellMin:    manager.rawCellMin,
                        cellMax:    manager.rawCellMax,
                        lowCutoff:  manager.rawMcuLowVoltageCutoff,
                        highCutoff: manager.rawMcuHighVoltageCutoff
                    )
                    .frame(height: isIPad ? GaugeMetrics.cellGaugeHeightIPad : GaugeMetrics.cellGaugeHeight)
                    .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.bottom, 20)
            .frame(height: bottomH)
        }
    }

    // MARK: - Portrait
    @ViewBuilder
    private func portraitLayout(
        geo: GeometryProxy,
        powerKW: Double,
        isCharging: Bool,
        powerColor: Color,
        normalizedPower: Double
    ) -> some View {
        // barHeight drives Power/Temp row height; gaugeSize fills whatever Energy space remains
        let barHeight: CGFloat = min(geo.size.height * 0.15, isIPad ? 200.0 : 110.0)
        let tempW: CGFloat = isIPad ? 72.0 : 46.0
        let maxGauge: CGFloat = isIPad ? GaugeMetrics.socGaugeMaxIPad : GaugeMetrics.socGaugeMaxPhone
        // Cap by available height so fixed sections (Power, Cells, Status) stay visible on small screens.
        let gaugeSize = max(60, min(geo.size.width * 0.80, maxGauge, geo.size.height - 390))

        VStack(spacing: 10) {

            // ── SOC gauge (prominent, centered) ──
            VStack(spacing: 6) {
                Text("Energy")
                    .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f kWh", manager.rawAvailableEnergyKwh))
                    .font(.system(size: isIPad ? 26 : 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                if isIPad { Spacer(minLength: 0) }
                Gauge(value: Double(manager.rawSOCPercentage), in: 0...100) {
                    Text("Charge")
                } currentValueLabel: {
                    Text("\(manager.rawSOCPercentage)%")
                }
                .gaugeStyle(AdaptiveSemicircleSoCStyle(valueFontSize: isIPad ? 64 : 44))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.rawSOCPercentage)
                .frame(width: gaugeSize, height: gaugeSize)
                if isIPad { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)

            Divider()

            // ── Power | Temp  (top)  /  Pack  (bottom) ──
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {

                    // Power column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Power")
                            .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                        HStack(alignment: .center, spacing: 8) {
                            PowerBarView(
                                normalizedPower: normalizedPower,
                                powerColor: powerColor,
                                thresholds: [0, 10, 100, 500],
                                barHeight: barHeight,
                                barWidth: isIPad ? 20 : 14
                            )
                            Text(String(format: "%.2f kW", abs(powerKW)))
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.black)
                                .foregroundColor(powerColor)
                        }
                        .frame(maxWidth: .infinity, alignment: isIPad ? .center : .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    // Temp column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temp")
                            .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                        TemperatureGaugeView(temp1: manager.rawMcuLowTemp, temp2: manager.rawMcuHighTemp)
                            .frame(width: tempW, height: barHeight)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: isIPad ? max(geo.size.height * 0.25, barHeight + 80) : nil)

                Divider()
                    .padding(.vertical, 6)

                // Pack row
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pack")
                        .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Text(String(format: "%.1fV", manager.rawPackVoltage))
                        Text(String(format: "%.1fA", manager.rawPackCurrent))
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 12)

            Divider()

            // ── Cell voltage range ──
            VStack(alignment: .leading, spacing: 6) {
                Text("Cells")
                    .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                CellVoltageRangeGaugeView(
                    cellMin:    manager.rawCellMin,
                    cellMax:    manager.rawCellMax,
                    lowCutoff:  manager.rawMcuLowVoltageCutoff,
                    highCutoff: manager.rawMcuHighVoltageCutoff
                )
                .frame(height: isIPad ? GaugeMetrics.cellGaugeHeightIPad : GaugeMetrics.cellGaugeHeight)
            }
            .padding(.horizontal, 12)

            Divider()

            // ── Status ──
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.system(size: isIPad ? 16 : 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                HStack(alignment: .center, spacing: 16) {
                    Text(manager.connectionStatus)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(
                            manager.isConnected ? Color("Primary Green") :
                            manager.connectionStatus == String(localized: "Bluetooth Off") ? .red : .orange
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, 8)
                    Spacer()
                    if manager.hasReceivedStatus {
                        Button {
                            showingHealth = true
                        } label: {
                            Image(systemName: anyAlert ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                .font(.system(size: isIPad ? 36 : 24, weight: .semibold))
                                .foregroundColor(anyAlert ? .red : Color("Primary Green"))
                        }
                        .buttonStyle(.plain)
                    }
                    if manager.scanTimedOut {
                        Button {
                            manager.retryScanning()
                        } label: {
                            Text("Retry")
                                .font(.system(size: isIPad ? 16 : 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    infoButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func calculateLogProgress(for value: Double) -> Double {
        guard value > scaleThresholds[0] else { return 0.0 }
        guard value < scaleThresholds.last! else { return 1.0 }
        let segmentWeight = 1.0 / Double(scaleThresholds.count - 1)
        for i in 0..<scaleThresholds.count - 1 {
            let lo = scaleThresholds[i], hi = scaleThresholds[i + 1]
            if value >= lo && value <= hi {
                let local = lo == 0
                    ? (value - lo) / (hi - lo)
                    : (log(value) - log(lo)) / (log(hi) - log(lo))
                return (Double(i) + local) * segmentWeight
            }
        }
        return 0.0
    }
}

// MARK: - Shared sub-views

private struct PowerBarView: View {
    let normalizedPower: Double
    let powerColor: Color
    let thresholds: [Double]
    let barHeight: CGFloat
    var barWidth: CGFloat = 26

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: barWidth)
                    Capsule()
                        .fill(powerColor)
                        .frame(width: barWidth, height: geo.size.height * normalizedPower)
                        .shadow(color: powerColor.opacity(0.15), radius: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: normalizedPower)
                }
                .frame(maxWidth: barWidth)
            }
            .frame(width: barWidth, height: barHeight)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(thresholds.reversed(), id: \.self) { threshold in
                    Text("\(Int(threshold))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxHeight: .infinity,
                               alignment: threshold == thresholds.last  ? .top
                                        : threshold == thresholds.first ? .bottom
                                        : .center)
                }
            }
            .frame(height: barHeight)
        }
    }
}

// MARK: - App Info Sheet

private struct AppInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let manager: OBD2ConnectionManager

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (Build \(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("EvDisplay")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            Divider()

            Group {
                infoRow(label: "App Version", value: appVersion)
                infoRow(label: "MCU Firmware", value: manager.mcuVersion == "--.--" ? "—" : manager.mcuVersion)
                infoRow(label: "Recommended Minimum", value: MCUConstants.minimumFirmwareString)
            }

            if manager.isDemoModeActive {
                Divider()
                Button {
                    manager.deactivateDemoMode()
                    dismiss()
                } label: {
                    Text("Exit Demo Mode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Spacer()
        }
        .padding()
        .preferredColorScheme(.dark)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Previews

#Preview("Landscape – iPad") {
    MCUDashboardCardView()
        .environment(OBD2ConnectionManager(isPreviewMock: true))
        .frame(width: 1000, height: 720)
        .padding()
        .background(Color("Shadow Background"))
}

#Preview("Portrait – iPad") {
    MCUDashboardCardView()
        .environment(OBD2ConnectionManager(isPreviewMock: true))
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.verticalSizeClass, .regular)
        .frame(width: 800, height: 1100)
        .padding()
        .background(Color("Shadow Background"))
}

#Preview("Portrait – iPhone") {
    MCUDashboardCardView()
        .environment(OBD2ConnectionManager(isPreviewMock: true))
        .frame(width: 390, height: 660)
        .padding()
        .background(Color("Shadow Background"))
}

#Preview("Portrait – iPhone SE") {
    MCUDashboardCardView()
        .environment(OBD2ConnectionManager(isPreviewMock: true))
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.verticalSizeClass, .regular)
        .frame(width: 343, height: 531)
        .padding()
        .background(Color("Shadow Background"))
}

#Preview("Landscape – iPhone SE") {
    MCUDashboardCardView()
        .environment(OBD2ConnectionManager(isPreviewMock: true))
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.verticalSizeClass, .compact)
        .frame(width: 643, height: 351)
        .padding()
        .background(Color("Shadow Background"))
}
