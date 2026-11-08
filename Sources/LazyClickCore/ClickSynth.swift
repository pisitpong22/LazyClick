import Foundation

/// One mechanical switch character. All times are seconds.
public struct ClickVoice: Sendable {
    public let name: String
    let tone: Double // Hz of the switch tick
    let decay: Double
    let noise: Double // 0...1, how much of the tick is noise rather than tone
    let releaseAfter: Double
}

/// Synthesizes a mouse click as a sharp press followed by a quieter, higher release.
public enum ClickSynth {
    public static let voices = [
        ClickVoice(name: "Mouse Click", tone: 2600, decay: 0.0035, noise: 0.6, releaseAfter: 0.075),
        ClickVoice(name: "Soft Click", tone: 1300, decay: 0.006, noise: 0.25, releaseAfter: 0.09),
        ClickVoice(name: "Sharp Click", tone: 4200, decay: 0.002, noise: 0.8, releaseAfter: 0.055),
    ]

    static let rate = 44_100.0
    static let tail = 0.03

    /// 16-bit mono PCM WAV, ready for `NSSound(data:)`.
    public static func wav(_ v: ClickVoice) -> Data {
        var samples = [Double](repeating: 0, count: Int((v.releaseAfter + tail) * rate))
        func strike(at start: Double, gain: Double, pitch: Double) {
            for i in Int(start * rate)..<samples.count {
                let t = Double(i) / rate - start
                let tick = (1 - v.noise) * sin(2 * .pi * v.tone * pitch * t) + v.noise * Double.random(in: -1...1)
                let body = 0.4 * exp(-t / (v.decay * 3)) * sin(2 * .pi * v.tone * pitch * 0.3 * t) // plastic shell
                samples[i] += gain * (exp(-t / v.decay) * tick + body)
            }
        }
        strike(at: 0, gain: 1, pitch: 1)
        strike(at: v.releaseAfter, gain: 0.6, pitch: 1.25)
        let peak = samples.map(abs).max() ?? 1

        var d = Data()
        func tag(_ s: String) { d.append(contentsOf: s.utf8) }
        func u16(_ x: UInt16) { withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ x: UInt32) { withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        tag("RIFF"); u32(36 + byteCount); tag("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16) // PCM, mono, 16-bit
        tag("data"); u32(byteCount)
        for s in samples { u16(UInt16(bitPattern: Int16(s / peak * 0.9 * 32767))) }
        return d
    }
}
