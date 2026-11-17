import Core

/// Battery readings are started and stopped by whoever shows them. While the tool is on, the charge limiter
/// gets a reading every 5 s (the sampler also reacts to plug events) and the MagSafe light follows it; turning the tool off
/// resets the helper and hands the light back.
@MainActor
final class BatteryTool: Tool {
    private let limiter: ChargeLimiter
    private let battery: BatterySampler
    private let led: LEDRunner
    private var loop: Task<Void, Never>?
    private var stopping: Task<Void, Never>?

    init(limiter: ChargeLimiter, battery: BatterySampler, led: LEDRunner) {
        self.limiter = limiter
        self.battery = battery
        self.led = led
    }

    func start() {
        let previousStop = stopping
        loop = Task { [limiter, battery, led] in
            await previousStop?.value // a quick off/on must not let the old "off" land after this "on"
            guard !Task.isCancelled else { return }
            await limiter.setToolEnabled(true)
            await led.setToolEnabled(true)
            while !Task.isCancelled {
                if limiter.wantsReadings { battery.hold("chargeLimiter") } else { battery.release("chargeLimiter") }
                await limiter.evaluate(battery.latest)
                await led.evaluate()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        let running = loop
        running?.cancel(); loop = nil
        battery.release("chargeLimiter")
        // Reset only after the loop has finished, so no evaluation can cut the adapter after it.
        stopping = Task { [limiter, led] in
            await running?.value
            await limiter.setToolEnabled(false)
            await led.setToolEnabled(false)
        }
    }
}
