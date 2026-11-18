import CoreGraphics
import Foundation

/// The 3D power flow: the Mac as a ringed planet at the origin, the charger as its sun, the battery and outside
/// devices as moons on inclined orbits. Pure maths (camera, projection, orbits) so it can be tested without drawing.
public struct Vec3: Equatable, Sendable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func * (a: Vec3, k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var unit: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
    public func rotX(_ a: Double) -> Vec3 { Vec3(x, y * cos(a) - z * sin(a), y * sin(a) + z * cos(a)) }
    public func rotY(_ a: Double) -> Vec3 { Vec3(x * cos(a) + z * sin(a), y, -x * sin(a) + z * cos(a)) }
    public func rotZ(_ a: Double) -> Vec3 { Vec3(x * cos(a) - y * sin(a), x * sin(a) + y * cos(a), z) }
}

/// Where the viewer is looking from. Yaw turns round the planet's axis, pitch tilts over it (kept short of the poles).
public struct SpaceCamera: Equatable, Sendable {
    public var yaw = 0.5, pitch = 0.42
    public static let maxPitch = 1.35, distance = 16.0
    public init(yaw: Double = 0.5, pitch: Double = 0.42) { self.yaw = yaw; self.pitch = min(max(pitch, -Self.maxPitch), Self.maxPitch) }

    /// This camera turned by a drag of `dx`, `dy` points.
    public func dragged(_ dx: Double, _ dy: Double) -> SpaceCamera { SpaceCamera(yaw: yaw + dx * 0.008, pitch: pitch + dy * 0.008) }

    /// World to camera space; +z points at the viewer, so z < 0 is behind the planet's centre.
    public func view(_ v: Vec3) -> Vec3 { v.rotY(yaw).rotX(pitch) }

    /// Camera space to the screen: `center` is where the planet sits, `scale` points per world unit at the planet.
    /// Returns the point and the perspective factor (bigger is nearer).
    public func project(_ c: Vec3, center: CGPoint, scale: Double) -> (point: CGPoint, s: Double) {
        let s = Self.distance / (Self.distance - c.z)
        return (CGPoint(x: center.x + c.x * scale * s, y: center.y - c.y * scale * s), s)
    }
}

/// One body circling the planet: orbit radius and inclination (world units, radians), and its angle on the orbit.
public struct SpaceOrbit: Equatable, Sendable {
    public var radius: Double, inclination: Double, angle: Double
    public init(radius: Double, inclination: Double, angle: Double) { self.radius = radius; self.inclination = inclination; self.angle = angle }

    public func position(at a: Double? = nil) -> Vec3 {
        let a = a ?? angle
        return Vec3(cos(a) * radius, 0, sin(a) * radius).rotX(inclination)
    }

    /// The angle on this orbit whose point lands nearest `target` on screen: dragging a moon slides it along its orbit.
    public func angle(nearest target: CGPoint, camera: SpaceCamera, center: CGPoint, scale: Double) -> Double {
        var best = angle, dist = Double.infinity
        for i in 0..<180 {
            let a = Double(i) / 180 * 2 * .pi
            let p = camera.project(camera.view(position(at: a)), center: center, scale: scale).point
            let d = hypot(p.x - target.x, p.y - target.y)
            if d < dist { dist = d; best = a }
        }
        return best
    }
}

public enum PowerSpace {
    /// The planet's axial tilt: its bands and ring lie in this plane.
    public static let tilt = 0.38
    /// World units across the whole system, used to fit it into the map.
    public static let span = 13.2
    public static let height: CGFloat = 300

    /// Default orbits. The charger, as the sun, is furthest out; outside devices fill the slots in order.
    public static let sun = SpaceOrbit(radius: 5.4, inclination: 0.16, angle: 2.5)
    public static let battery = SpaceOrbit(radius: 3.05, inclination: 0.3, angle: 1.5)
    public static let devices = [SpaceOrbit(radius: 3.75, inclination: -0.22, angle: 0.15),
                                 SpaceOrbit(radius: 4.5, inclination: 0.1, angle: -1.2),
                                 SpaceOrbit(radius: 2.45, inclination: -0.35, angle: 3.6)]

    /// The bodies for a reading's nodes: the charger, the battery, and one moon per reported outside stream (at most three).
    public static func orbits(streams: [PowerStream], angles: [FlowNodeID: Double] = [:]) -> [(FlowNodeID, SpaceOrbit)] {
        var out: [(FlowNodeID, SpaceOrbit)] = [(.charger, sun), (.battery, battery)]
        for (i, s) in streams.filter({ $0.watts != nil }).prefix(devices.count).enumerated() { out.append((.stream(s.title), devices[i])) }
        return out.map { id, o in
            var o = o
            if let a = angles[id], a.isFinite { o.angle = a }
            return (id, o)
        }
    }

    /// A point on the ring plane, `r` planet radii out, at angle `a`.
    public static func ringPoint(_ r: Double, _ a: Double) -> Vec3 { Vec3(cos(a) * r, 0, sin(a) * r).rotZ(tilt) }

    /// A point on the planet's surface at latitude `lat`, longitude `lon`, following the tilt.
    public static func surface(lat: Double, lon: Double) -> Vec3 { Vec3(cos(lon) * cos(lat), sin(lat), sin(lon) * cos(lat)).rotZ(tilt) }

    /// The arc power travels on between two bodies: a quadratic curve lifted above the ring plane, `t` from 0 to 1.
    public static func arc(_ a: Vec3, _ b: Vec3, _ t: Double) -> Vec3 {
        let lift = 0.9 + hypot(a.x - b.x, a.z - b.z) * 0.12
        let c = (a + b) * 0.5 + Vec3(0, lift, 0)
        let u = 1 - t
        return a * (u * u) + c * (2 * u * t) + b * (t * t)
    }

    /// Where an arc meets the planet, just above its surface on the side facing `p`.
    public static func landing(toward p: Vec3) -> Vec3 { p.unit * 1.12 }

    /// Moon radius in points at the planet's depth: grows with the square root of its watts.
    public static func moonSize(_ watts: Double?) -> Double { 4.5 + (max(watts ?? 0, 0)).squareRoot() * 1.4 }
}

/// What the 3D view remembers between launches: the camera and where each moon was dragged to on its orbit.
public struct SpaceView: Equatable, Sendable {
    public static let storageKey = "powerFlow.space"
    public var camera = SpaceCamera()
    public var angles: [FlowNodeID: Double] = [:]
    public init(camera: SpaceCamera = SpaceCamera(), angles: [FlowNodeID: Double] = [:]) { self.camera = camera; self.angles = angles }

    public var isDefault: Bool { camera == SpaceCamera() && angles.isEmpty }

    public init(json: String) {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return }
        if let c = raw["camera"], c.count == 2, c.allSatisfy(\.isFinite) { camera = SpaceCamera(yaw: c[0], pitch: c[1]) }
        for (k, v) in raw where k.hasPrefix("moon:") {
            if let id = FlowNodeID(storageKey: String(k.dropFirst(5))), let a = v.first, a.isFinite { angles[id] = a }
        }
    }

    public var json: String {
        guard !isDefault else { return "" }
        var raw: [String: [Double]] = ["camera": [camera.yaw.truncatingRemainder(dividingBy: 2 * .pi), camera.pitch]]
        for (id, a) in angles { raw["moon:" + id.storageKey] = [a] }
        guard let data = try? JSONEncoder().encode(raw) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
