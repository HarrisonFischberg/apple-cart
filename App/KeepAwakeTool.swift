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

/// Quick toggles read the system when shown; nothing runs in the background.
@MainActor
final class QuickTogglesTool: Tool {
    func start() {}
    func stop() {}
}

/// Update checks and DNS flush run only when the user presses a button.
@MainActor
final class OnDemandTool: Tool {
    func start() {}
    func stop() {}
}
