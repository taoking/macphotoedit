import Foundation
import XCTest
@testable import MacPhotoStudio

final class VideoAudioTests: XCTestCase {
    func testAudioMixGainIsAttenuationOnlyAndNeverExceedsUnity() {
        XCTAssertEqual(VideoAudioGain.clamped(-100), -60)
        XCTAssertEqual(VideoAudioGain.clamped(-6), -6)
        XCTAssertEqual(VideoAudioGain.clamped(0), 0)
        XCTAssertEqual(VideoAudioGain.clamped(6), 0)
        XCTAssertEqual(VideoAudioGain.clamped(12), 0)

        XCTAssertEqual(VideoAudioGain.linearVolume(for: -60), 0.001, accuracy: 0.0001)
        XCTAssertEqual(VideoAudioGain.linearVolume(for: -6), 0.5012, accuracy: 0.001)
        XCTAssertEqual(VideoAudioGain.linearVolume(for: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(VideoAudioGain.linearVolume(for: 12), 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(VideoAudioGain.linearVolume(for: 12), 1)
    }

    func testPersistedLegacyPositiveAudioGainDecodesAsZeroDecibels() throws {
        let data = Data("{\"version\":2,\"audioGain\":12}".utf8)
        let state = try JSONDecoder().decode(VideoEditState.self, from: data)

        XCTAssertEqual(state.audioGain, 0)
        XCTAssertEqual(state.clampedAudioGain, 0)
    }
}
