import XCTest
@testable import Food

final class ObservationTests: XCTestCase {
    private let classifier = CaramelClassifier()

    private func stats(_ r: Int, _ g: Int, _ b: Int, glare: Double = 0, spread: Double = 0.05) -> FrameStats {
        FrameStats(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255, glareFraction: glare, lumaStdDev: spread)
    }

    // 以下颜色与 Tools/make_placeholders.sh 里的合成色块一致。
    // 它们只验证规则自洽，不代表对真实糖色的识别效果。

    func testSyntheticSwatchesClassify() {
        XCTAssertEqual(classifier.classify(stats(235, 200, 120)), .tooPale)
        XCTAssertEqual(classifier.classify(stats(170, 85, 25)), .nearTarget)
        XCTAssertEqual(classifier.classify(stats(70, 30, 14)), .maybeDark)
    }

    func testUnclearConditions() {
        XCTAssertEqual(classifier.classify(stats(232, 232, 232)), .unclear, "蒸汽/白光")
        XCTAssertEqual(classifier.classify(stats(12, 8, 5)), .unclear, "光线太暗")
        XCTAssertEqual(classifier.classify(stats(170, 85, 25, glare: 0.4)), .unclear, "反光")
        XCTAssertEqual(classifier.classify(stats(170, 85, 25, spread: 0.4)), .unclear, "选区混入锅沿")
        XCTAssertEqual(classifier.classify(stats(40, 90, 200)), .unclear, "锅面出框，拍到别的东西")
    }

    func testStabilizerNeedsConsecutiveFrames() {
        var stabilizer = ObservationStabilizer(requiredConsecutive: 3)
        XCTAssertNil(stabilizer.ingest(.nearTarget).display)
        XCTAssertNil(stabilizer.ingest(.nearTarget).display)
        // 中途被别的结果打断，重新计数。
        XCTAssertNil(stabilizer.ingest(.tooPale).display)
        XCTAssertNil(stabilizer.ingest(.nearTarget).announce)
        XCTAssertNil(stabilizer.ingest(.nearTarget).announce)
        let third = stabilizer.ingest(.nearTarget)
        XCTAssertEqual(third, .init(display: .nearTarget, announce: .nearTarget))
    }

    func testSameStateIsAnnouncedOnlyOnce() {
        var stabilizer = ObservationStabilizer(requiredConsecutive: 2)
        var announcements: [CaramelReading] = []
        let frames: [CaramelReading] = [
            .nearTarget, .nearTarget, .nearTarget, .nearTarget,   // 播报一次
            .unclear, .unclear, .unclear,                          // 蒸汽挡住：不播报
            .nearTarget, .nearTarget, .nearTarget,                 // 恢复后同一状态：不重复
            .maybeDark, .maybeDark, .maybeDark,                    // 新状态：播报一次
        ]
        for frame in frames {
            if let announce = stabilizer.ingest(frame).announce { announcements.append(announce) }
        }
        XCTAssertEqual(announcements, [.nearTarget, .maybeDark])
    }

    func testFlappingBetweenStatesDoesNotRepeatAnnouncements() {
        var stabilizer = ObservationStabilizer(requiredConsecutive: 2)
        var announcements: [CaramelReading] = []
        var displays: [CaramelReading?] = []
        for _ in 0..<3 {
            for frame: CaramelReading in [.nearTarget, .nearTarget, .maybeDark, .maybeDark] {
                let output = stabilizer.ingest(frame)
                displays.append(output.display)
                if let announce = output.announce { announcements.append(announce) }
            }
        }
        XCTAssertEqual(announcements, [.nearTarget, .maybeDark], "来回跳只各播报一次")
        XCTAssertEqual(displays.last, .maybeDark, "文字仍跟随最新稳定状态")
    }

    func testResetAllowsAnnouncingAgain() {
        var stabilizer = ObservationStabilizer(requiredConsecutive: 1)
        XCTAssertEqual(stabilizer.ingest(.nearTarget).announce, .nearTarget)
        stabilizer.reset()
        XCTAssertEqual(stabilizer.ingest(.nearTarget).announce, .nearTarget)
    }

    func testPaleAndUnclearAreNeverSpoken() {
        var stabilizer = ObservationStabilizer(requiredConsecutive: 1)
        XCTAssertNil(stabilizer.ingest(.tooPale).announce)
        XCTAssertNil(stabilizer.ingest(.unclear).announce)
        XCTAssertEqual(stabilizer.ingest(.unclear).display, .unclear)
    }

    func testAnalysisGateSamplesAtTwoFramesPerSecondAndSkipsBacklog() {
        let gate = AnalysisGate(framesPerSecond: 2)
        XCTAssertFalse(gate.shouldSample(at: 0), "未开启分析时不采样")
        gate.setEnabled(true)
        // 30 fps 连续送 3 秒的帧。
        let sampled = (0..<90).filter { gate.shouldSample(at: Double($0) / 30) }
        XCTAssertEqual(sampled.count, 6)
        gate.setEnabled(false)
        XCTAssertFalse(gate.shouldSample(at: 10))
    }

    func testVoicePhraseMatching() {
        let phrases = ["颜色到了", "到了", "可以了"]
        XCTAssertTrue(VoicePhraseMatcher.matches("颜色到了", phrases: phrases))
        XCTAssertTrue(VoicePhraseMatcher.matches("好 可以了", phrases: phrases))
        XCTAssertFalse(VoicePhraseMatcher.matches("颜色还没到", phrases: phrases))
        XCTAssertFalse(VoicePhraseMatcher.matches("还没到了吧", phrases: phrases))
        XCTAssertFalse(VoicePhraseMatcher.matches("等一下", phrases: phrases))
        XCTAssertFalse(VoicePhraseMatcher.matches("今天天气", phrases: phrases))
    }
}
