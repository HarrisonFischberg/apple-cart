import Core

/// Turning the tool off ends any session and releases the assertion.
@MainActor
final class KeepAwakeTool: Tool {
    private let keepAwake: KeepAwake
    init(_ keepAwake: KeepAwake) { self.keepAwake = keepAwake }
    func start() {}
    func stop() { keepAwake.stop(reason: "Tool turned off") }
}

/// The system monitor needs no setup: views hold and release its sampler.
@MainActor
final class SystemTool: Tool {
    func start() {}
    func stop() {}
}
