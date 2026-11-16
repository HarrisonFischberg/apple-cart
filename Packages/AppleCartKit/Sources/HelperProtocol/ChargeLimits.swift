/// Product limits shared by the app and the root helper. The helper clamps again on its side.
public enum ChargeLimits {
    public static let range = 20...100

    public static func clamped(_ percent: Int) -> Int {
        min(max(percent, range.lowerBound), range.upperBound)
    }
}

public enum FanLimits {
    /// A manual fan target never goes below the fan's own minimum running speed or above its maximum (both read from the SMC).
    public static func clampedMinimum(requested: Int, systemMinimum: Int, hardwareMaximum: Int) -> Int {
        min(max(requested, systemMinimum), hardwareMaximum)
    }
}
