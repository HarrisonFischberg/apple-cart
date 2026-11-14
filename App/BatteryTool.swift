import Core

/// Battery readings need no setup: sampling is started and stopped by whoever shows them.
@MainActor
final class BatteryTool: Tool {
    func start() {}
    func stop() {}
}
