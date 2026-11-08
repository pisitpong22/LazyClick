import AppKit
import XCTest
@testable import LazyClickCore

final class ClickSynthTests: XCTestCase {
    func testEveryVoiceDecodesAndHasPressAndRelease() throws {
        for v in ClickSynth.voices {
            let wav = ClickSynth.wav(v)
            let sound = try XCTUnwrap(NSSound(data: wav), v.name)
            XCTAssertEqual(sound.duration, v.releaseAfter + ClickSynth.tail, accuracy: 0.01, v.name)

            let pcm = wav.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
            let release = Int(v.releaseAfter * ClickSynth.rate), window = Int(0.002 * ClickSynth.rate)
            func level(_ r: Range<Int>) -> Int { pcm[r].map { abs(Int($0)) }.max() ?? 0 }
            XCTAssertEqual(level(0..<pcm.count), Int(0.9 * 32767), accuracy: 1, "\(v.name) is normalized")
            XCTAssertGreaterThan(level(release..<release + window), level(release - window..<release) * 3,
                                 "\(v.name) has a distinct release")
        }
    }
}
