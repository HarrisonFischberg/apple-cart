import Foundation

/// Plain-words detail for one tile of the power flow map, shown when the owner taps it. Only states what the reading says.
public struct FlowExplanation: Equatable, Sendable {
    public let title: String
    public let value: String
    public let text: String
    public let facts: [String]
}

public enum FlowExplain {
    public static func make(_ id: FlowNodeID, reading r: BatteryReading?, pausedAt: Int?, streams: [PowerStream]) -> FlowExplanation {
        guard let r else { return FlowExplanation(title: title(id), value: "—", text: "No battery reading yet.", facts: []) }
        switch id {
        case .charger:
            let rating = r.adapterWatts.map { "Charger rating: \($0) W" }
            if !r.isPluggedIn {
                return FlowExplanation(title: "Charger", value: "—", text: "No charger is connected, so the Mac runs on the battery.", facts: [])
            }
            if let n = pausedAt {
                return FlowExplanation(title: "Charger", value: PowerFlow.watts(0),
                                       text: "Your charge limit is holding the charger off at \(n)%, so it supplies nothing and the Mac runs on the battery. Charging starts again when the level drops a few points below the limit, or when you tap Top Up.",
                                       facts: [rating].compactMap { $0 })
            }
            let supplied = PowerFlows(r).chargerToMac.map { $0 + (PowerFlows(r).chargerToBattery ?? 0) }
            return FlowExplanation(title: "Charger", value: PowerFlow.watts(supplied),
                                   text: "Power coming in from the charger right now. It feeds the Mac first. Anything left over charges the battery.",
                                   facts: [rating].compactMap { $0 })
        case .mac:
            return FlowExplanation(title: "Mac uses", value: PowerFlow.watts(r.systemWatts),
                                   text: "Everything this Mac is using right now: the chip, screen, drives, Wi-Fi, fans and anything plugged into its ports. macOS reports one total, so it cannot be split further here.",
                                   facts: [])
        case .battery:
            let level = "Charge: \(r.shownPercentText)"
            if r.batteryWatts > 0.05 {
                return FlowExplanation(title: "Battery", value: "+" + PowerFlow.watts(r.batteryWatts),
                                       text: "The battery is charging at this rate. The charger is giving it more than the Mac needs.", facts: [level])
            }
            if r.batteryWatts < -0.05 {
                return FlowExplanation(title: "Battery", value: "−" + PowerFlow.watts(r.batteryWatts),
                                       text: pausedAt != nil ? "The battery is powering the Mac while the charger is held off by your limit."
                                                              : "The battery is giving power to the Mac. Either the charger is not connected, or it cannot cover everything the Mac is doing.",
                                       facts: [level])
            }
            return FlowExplanation(title: "Battery", value: PowerFlow.watts(0), text: "The battery is neither charging nor giving power right now.", facts: [level])
        case .more:
            return FlowExplanation(title: "Rest of Mac", value: "—", text: "", facts: [])
        case .stream(let name):
            let w = streams.first { $0.title == name }?.watts
            return FlowExplanation(title: name, value: PowerFlow.watts(w), text: streamText(name), facts: [])
        }
    }

    static func title(_ id: FlowNodeID) -> String {
        switch id {
        case .charger: "Charger"
        case .mac: "Mac uses"
        case .battery: "Battery"
        case .more: "Rest of Mac"
        case .stream(let n): n
        }
    }

    private static func streamText(_ name: String) -> String {
        switch name {
        case "USB": "Power this Mac is giving to devices on its USB-C ports, for example a phone that is charging. It is part of the Mac's total."
        case "Charger loss": "Power lost as heat in the charger and cable while it converts wall power for the Mac. A little is normal, and it grows with load. It is not extra use by the Mac, and macOS only estimates it."
        case "SoC": "Power used by the chip itself (processor, graphics and memory). Part of the Mac's total."
        default: "A part of the Mac's power that macOS reports on its own. It is included in the Mac's total."
        }
    }
}
