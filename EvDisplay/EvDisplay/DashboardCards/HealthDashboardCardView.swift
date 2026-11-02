//
//  HealthDashboardCardView.swift
//  EvDisplay
//
//  Created by Sylvia Wake-Hood on 7/27/26.
//

import SwiftUI
import OBD2Kit

struct HealthDashboardCardView: View {
    @Environment(\.dismiss) var dismiss

    @Environment(OBD2ConnectionManager.self) private var environmentManager: OBD2ConnectionManager?
    @State private var localPreviewSource = OBD2ConnectionManager(isPreviewMock: true)
    
    private var manager: OBD2ConnectionManager {
        environmentManager ?? localPreviewSource
    }
    
    private var activeAlerts: [String] {
        var alerts: [String] = []
        if manager.alertHardware == 1 { alerts.append("Hardware Fault") }
        if manager.alertCCensus == 1 { alerts.append("Cell Census Fault") }
        if manager.alertTCensus == 1 { alerts.append("Thermistor Census Fault") }
        if manager.alertHVC == 1 { alerts.append("High Voltage Cutoff") }
        if manager.alertLVC == 1 { alerts.append("Low Voltage Cutoff") }
        if manager.alertHiTemp == 1 { alerts.append("High Temperature") }
        if manager.alertLoTemp == 1 { alerts.append("Low Temperature") }
        return alerts
    }
    
    private var healthColor: Color {
        activeAlerts.isEmpty ? Color("Primary Green") : .red
    }
    
    private var alertItems: [(label: String, isActive: Bool)] {
        [
            ("Hardware Fault", manager.alertHardware == 1),
            ("Cell Census Fault", manager.alertCCensus == 1),
            ("Thermistor Census Fault", manager.alertTCensus == 1),
            ("High Voltage Cutoff", manager.alertHVC == 1),
            ("Low Voltage Cutoff", manager.alertLVC == 1),
            ("High Temperature", manager.alertHiTemp == 1),
            ("Low Temperature", manager.alertLoTemp == 1)
        ]
    }
    
    var body: some View {
        BaseDashboardCard(title: "Health", themeColor: healthColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activeAlerts.isEmpty ? "No Active Alerts" : "Active Alerts")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(healthColor)

                    Spacer()

                    Text("\(activeAlerts.count)/7")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(alertItems, id: \.label) { item in
                        HealthAlertFlagView(label: item.label, isActive: item.isActive)
                    }
                }
            }
            .padding(.horizontal)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss()}) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(10)
            }
        }
    }
}

private struct HealthAlertFlagView: View {
    let label: String
    let isActive: Bool
    
    private var color: Color {
        isActive ? .red : Color("Primary Green")
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(isActive ? 0.5 : 0.25), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

#Preview() {
    HealthDashboardCardView()
        .environment(OBD2ConnectionManager(isPreviewMock: true))
        .frame(width: 400, height: 180)
        .padding()
}
