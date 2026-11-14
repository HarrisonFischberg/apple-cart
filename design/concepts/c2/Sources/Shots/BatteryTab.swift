import SwiftUI
import ConceptShared

struct BatteryTab: View {
    @State private var limit = Mock.limit
    @State private var heat = true
    @State private var sailing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                Dial(limit: $limit, charge: Mock.percent)
                VStack(spacing: 0) {
                    Reading(label: "Charge", value: "\(Int(Mock.percent))%"); Hair()
                    Reading(label: "Hardware", value: "\(Mock.hardwarePercent)%"); Hair()
                    Reading(label: "Temperature", value: "\(Mock.tempC) °C"); Hair()
                    Reading(label: "Heat limit", value: "\(Int(Mock.heatLimitC)) °C"); Hair()
                    Reading(label: "To Mac", value: "\(Mock.wattsToMac) W"); Hair()
                    Reading(label: "To battery", value: "\(Mock.wattsToBattery) W"); Hair()
                    Reading(label: "Adapter rating", value: "\(Mock.adapterRatedWatts) W")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Label { Text(Mock.stateTitle).font(hn(15, true)) } icon: { Image(systemName: "pause.fill").font(.system(size: 12)) }
                Text(Mock.stateReason).font(hn(12)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(T.orangeText)
            .accessibilityElement(children: .combine)

            Grouped {
                row("Top up", trailing: Image(systemName: "chevron.right"))
                Hair()
                row("Discharge to...", trailing: Image(systemName: "chevron.right"))
                Hair()
                Toggle(isOn: $heat) {
                    HStack(spacing: 8) { Text("Heat protection"); Text("\(Int(Mock.heatLimitC)) °C").foregroundStyle(T.ink2) }
                }
                .toggleStyle(switchStyle()).font(hn(13)).foregroundStyle(T.ink).padding(.horizontal, 12).frame(height: 32)
                Hair()
                Toggle(isOn: $sailing) {
                    HStack(spacing: 8) { Text("Sailing range"); Text("5%").foregroundStyle(T.ink2) }
                }
                .toggleStyle(switchStyle()).font(hn(13)).foregroundStyle(T.ink).padding(.horizontal, 12).frame(height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Charge, last 24 hours").font(hn(13, true)).foregroundStyle(T.ink)
                    Spacer()
                    Rectangle().fill(T.ink.opacity(0.10)).frame(width: 12, height: 10)
                    Text("Plugged in").font(hn(11)).foregroundStyle(T.ink2)
                    Text("- - Limit \(limit)%").font(hn(11)).foregroundStyle(T.ink2).padding(.leading, 6)
                }
                HistoryChart(limit: limit)
            }

            Grouped {
                HStack(spacing: 0) {
                    detail("Cycles", "\(Mock.cycles)"); VHair()
                    detail("Maximum capacity", "\(Mock.maxCapacityPercent)%"); VHair()
                    detail("Health", Mock.health)
                }
                .frame(height: 40)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func row(_ title: String, trailing: Image) -> some View {
        Button { } label: {
            HStack {
                Text(title).font(hn(13)).foregroundStyle(T.ink)
                Spacer()
                trailing.font(.system(size: 11, weight: .regular)).foregroundStyle(T.ink2)
            }
            .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(hn(11)).foregroundStyle(T.ink2)
            Text(value).font(hn(14, true)).foregroundStyle(T.ink)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
