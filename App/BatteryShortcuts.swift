import AppIntents
import Core

/// Read-only Shortcuts actions. Write actions need the charging helper and are not built yet.
struct GetBatteryPercentage: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Percentage"
    static let description = IntentDescription("The battery charge as macOS shows it.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let r = BatteryReader.read() else { throw BatteryShortcutError.noBattery }
        return .result(value: r.percent)
    }
}

struct GetChargeLimit: AppIntent {
    static let title: LocalizedStringResource = "Get Charge Limit"
    static let description = IntentDescription("The charge limit saved in Apple Cart. Saved does not mean enforced until the charging helper exists.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: ChargeLimitSettings().limit)
    }
}

struct GetChargingState: AppIntent {
    static let title: LocalizedStringResource = "Get Charging State"
    static let description = IntentDescription("Charging, plugged in not charging, or on battery.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let r = BatteryReader.read() else { throw BatteryShortcutError.noBattery }
        return .result(value: r.stateText.lowercased())
    }
}

struct GetBatteryTemperature: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Temperature"
    static let description = IntentDescription("The battery temperature in degrees Celsius, when macOS provides it.")

    func perform() async throws -> some IntentResult & ReturnsValue<Double?> & ProvidesDialog {
        guard let r = BatteryReader.read() else { throw BatteryShortcutError.noBattery }
        guard let t = r.temperatureC else { return .result(value: nil, dialog: "macOS does not provide a battery temperature on this Mac.") }
        return .result(value: t, dialog: "\(Int(t.rounded())) degrees Celsius")
    }
}

enum BatteryShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case noBattery
    var localizedStringResource: LocalizedStringResource { "This Mac has no battery." }
}

struct AppleCartShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetBatteryPercentage(), phrases: ["Battery percentage in \(.applicationName)", "How full is my battery in \(.applicationName)"],
                    shortTitle: "Battery Percentage", systemImageName: "battery.75percent")
        AppShortcut(intent: GetChargeLimit(), phrases: ["Charge limit in \(.applicationName)"],
                    shortTitle: "Charge Limit", systemImageName: "gauge.with.dots.needle.67percent")
        AppShortcut(intent: GetChargingState(), phrases: ["Charging state in \(.applicationName)"],
                    shortTitle: "Charging State", systemImageName: "bolt.batteryblock")
        AppShortcut(intent: GetBatteryTemperature(), phrases: ["Battery temperature in \(.applicationName)"],
                    shortTitle: "Battery Temperature", systemImageName: "thermometer.medium")
    }
}
