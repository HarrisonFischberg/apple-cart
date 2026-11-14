import SwiftUI
import ConceptShared

struct BatteryTab: View {
    @State private var limit = Mock.limit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CourseMap(limit: $limit).frame(height: 134)
            MapKey().padding(.top, 2)
            nowRow.padding(.top, 10)
            Legend().padding(.top, 10)
            buttons.padding(.top, 10)
            flow.padding(.top, 10)
            details.padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }

    private var nowRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(Mock.percent))").font(T.num(36, .bold))
                    Text("%").font(T.num(18, .semibold))
                }
            }
            .foregroundStyle(T.ink).frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.high").font(.system(size: 12, weight: .regular))
                    Text(Mock.stateTitle).font(.system(size: 13.5, weight: .semibold))
                }.foregroundStyle(T.oliveText)
                Text(Mock.stateReason).font(.system(size: 12)).foregroundStyle(T.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.oliveFill.opacity(0.17)))
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { } label: {
                Label("Top up", systemImage: "bolt.fill").font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .foregroundStyle(T.ground).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(T.ink))
            }
            Button { } label: {
                Label("Discharge to…", systemImage: "arrow.down.to.line").font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .foregroundStyle(T.ink).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(T.ink.opacity(0.09)))
            }
        }.buttonStyle(PressStyle())
    }

    private var flow: some View {
        HStack(spacing: 0) {
            flowCell("Adapter", "\(Mock.adapterRatedWatts) W", "rating")
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(T.blueText).frame(width: 22)
            flowCell("To Mac", String(format: "%.1f W", Mock.wattsToMac), nil)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(T.blueText).frame(width: 22)
            flowCell("To battery", String(format: "%.1f W", Mock.wattsToBattery), nil)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.blueFill.opacity(0.13)))
        .accessibilityElement(children: .combine)
    }

    private func flowCell(_ label: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundStyle(T.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(T.num(19, .bold)).foregroundStyle(T.blueText)
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(T.ink2) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(spacing: 0) {
            line("Temperature", valueText: String(format: "%.1f °C", Mock.tempC), tail: "heat limit \(Int(Mock.heatLimitC)) °C", caution: true)
            line("Hardware percentage", valueText: String(format: "%.1f%%", Mock.hardwarePercent), tail: "shown as \(Int(Mock.percent))%", caution: false)
            HStack(spacing: 0) {
                cell("Cycles", "\(Mock.cycles)")
                cell("Maximum capacity", "\(Mock.maxCapacityPercent)%")
                cell("Health", Mock.health)
            }.padding(.top, 4)
        }
    }

    private func line(_ l: String, valueText: String, tail: String, caution: Bool) -> some View {
        HStack(spacing: 6) {
            Text(l).foregroundStyle(T.ink2)
            Spacer(minLength: 8)
            Text(valueText).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(caution ? T.oliveText : T.ink)
            Text(tail).foregroundStyle(T.ink2)
        }
        .font(.system(size: 12)).frame(height: 19)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l).font(.system(size: 11)).foregroundStyle(T.ink2)
            Text(v).font(T.num(16, .semibold)).foregroundStyle(T.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
