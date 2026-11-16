import Core
import Foundation

/// While the Fan speed tool is on, reads the fans and temperatures every 5 s (off the main thread, read only) and feeds
/// the runner. Turning the tool off hands the fans back to macOS.
@MainActor
final class FanTool: Tool {
    private let runner: FanRunner
    private var loop: Task<Void, Never>?
    private var stopping: Task<Void, Never>?
    private nonisolated static let temperatures = LiveSystemSource()

    init(runner: FanRunner) { self.runner = runner }

    static func sample() async -> FanSample {
        await Task.detached {
            let chips = temperatures.chipTemperatures()
            let thermal = ProcessInfo.processInfo.thermalState
            return FanSample(reading: FanSensors.read(),
                             temperatures: FanTemperatures(cpu: chips.cpu, gpu: chips.gpu, battery: BatterySensors.read().temperatureC,
                                                           hottestSensor: chips.hottest),
                             thermalPressure: thermal == .serious || thermal == .critical)
        }.value
    }

    func start() {
        let previousStop = stopping
        loop = Task { [runner] in
            await previousStop?.value // a quick off/on must not let the old "off" land after this "on"
            guard !Task.isCancelled else { return }
            await runner.setToolEnabled(true)
            while !Task.isCancelled {
                await runner.evaluate(await Self.sample())
                try? await Task.sleep(for: .seconds(FanRunner.evaluateEvery))
            }
        }
    }

    func stop() {
        let running = loop
        running?.cancel(); loop = nil
        // Reset only after the loop has finished, so no evaluation can set a speed after it.
        stopping = Task { [runner] in
            await running?.value
            await runner.setToolEnabled(false)
        }
    }
}
