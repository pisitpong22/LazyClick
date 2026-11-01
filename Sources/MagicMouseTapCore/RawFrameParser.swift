import Foundation

/// Reads MultitouchSupport's `MTTouch` records straight from raw memory using fixed byte offsets
/// (no Swift struct whose layout we would have to trust). Layout as documented by the community
/// and cross-checked against two open-source projects (see README): 96-byte records.
///
///   0 Int32 frame          16 Int32 pathIndex/identifier   32 Float normX  36 Float normY
///   8 Double timestamp     20 Int32 stage                   40 Float velX   44 Float velY
///                          24 Int32 fingerID  28 Int32 handID    ... 92 Float zDensity
public enum MTLayout {
    public static let stride = 96
    public static let identifierOffset = 16
    public static let stageOffset = 20
    public static let xOffset = 32
    public static let yOffset = 36
    public static let maxPlausibleContacts = 16
    /// MTTouchState: 3 = making contact, 4 = touching. Other values are hover / breaking / lingering.
    public static func isDown(stage: Int32) -> Bool { stage == 3 || stage == 4 }
}

public enum RawFrameParser {
    public enum Result: Equatable { case ok, implausible }

    /// Appends *down* contacts to `out` (cleared first). Returns `.implausible` if the data does not look
    /// like MTTouch records, which indicates an ABI mismatch on this macOS version.
    public static func parse(_ base: UnsafeRawPointer?, count: Int, into out: inout [Contact]) -> Result {
        out.removeAll(keepingCapacity: true)
        if count == 0 { return .ok }
        guard let base, count > 0, count <= MTLayout.maxPlausibleContacts else { return .implausible }
        for i in 0..<count {
            let rec = base + i * MTLayout.stride
            let id = rec.loadUnaligned(fromByteOffset: MTLayout.identifierOffset, as: Int32.self)
            let stage = rec.loadUnaligned(fromByteOffset: MTLayout.stageOffset, as: Int32.self)
            let x = rec.loadUnaligned(fromByteOffset: MTLayout.xOffset, as: Float.self)
            let y = rec.loadUnaligned(fromByteOffset: MTLayout.yOffset, as: Float.self)
            guard x.isFinite, y.isFinite, x > -0.05, x < 1.05, y > -0.05, y < 1.05,
                  stage >= 0, stage <= 7 else {
                out.removeAll(keepingCapacity: true)
                return .implausible
            }
            if MTLayout.isDown(stage: stage) {
                out.append(Contact(id: id, x: x, y: y))
            }
        }
        return .ok
    }
}
