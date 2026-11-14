/// Product limits shared by the app and the root helper. The helper clamps again on its side.
public enum ChargeLimits {
    public static let range = 20...100

    public static func clamped(_ percent: Int) -> Int {
        min(max(percent, range.lowerBound), range.upperBound)
    }
}

public enum FanLimits {
    /// Fan safe mode only raises speed above the system curve, never below it.
    public static func clampedMinimum(requested: Int, systemMinimum: Int, hardwareMaximum: Int) -> Int {
        min(max(requested, systemMinimum), hardwareMaximum)
    }
}
