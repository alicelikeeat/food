import CoreVideo
import Foundation

// 糖色观察：基于锅面中心选区的本地颜色规则。
// 这是「视觉辅助原型」，不是模型识别。阈值来自合成色块，尚未用实拍素材标定。
// 输出只用于提示，任何结果都不会替用户换步。

/// 选区的颜色统计，全部归一到 0...1。
struct FrameStats: Equatable {
    var r: Double
    var g: Double
    var b: Double
    /// 接近过曝的采样点占比（反光）。
    var glareFraction: Double
    /// 亮度标准差。过大说明选区里混进了锅沿、锅铲等，颜色不可信。
    var lumaStdDev: Double
}

enum CaramelReading: String, Codable, Equatable {
    case tooPale
    case nearTarget
    case maybeDark
    /// 失焦、反光、蒸汽、出框或光线不合适：不可判定。
    case unclear

    var hint: String {
        switch self {
        case .tooPale: return "颜色还偏浅"
        case .nearTarget: return "接近目标"
        case .maybeDark: return "可能偏深"
        case .unclear: return "看不清"
        }
    }

    /// 只有这两种值得出声；偏浅和看不清只显示文字。
    var spoken: String? {
        switch self {
        case .nearTarget: return "颜色接近目标了，对照示范看一眼。"
        case .maybeDark: return "颜色可能偏深了，留意一下。"
        case .tooPale, .unclear: return nil
        }
    }
}

struct CaramelThresholds: Equatable {
    var minBrightness = 0.10
    var maxGlare = 0.20
    var maxLumaStdDev = 0.28
    /// 饱和度低且亮：蒸汽、空锅或白光。
    var minSaturation = 0.18
    var hueRange: ClosedRange<Double> = 5...65
    /// 亮且偏黄：糖刚化开。
    var paleMinBrightness = 0.62
    var paleMinHue = 32.0
    /// 暗或偏红褐：可能过头。
    var darkMaxBrightness = 0.34
    var darkMaxHue = 12.0
}

struct CaramelClassifier {
    var thresholds = CaramelThresholds()

    func classify(_ s: FrameStats) -> CaramelReading {
        let t = thresholds
        let maxC = max(s.r, s.g, s.b)
        let minC = min(s.r, s.g, s.b)
        let delta = maxC - minC
        guard maxC >= t.minBrightness, s.glareFraction <= t.maxGlare, s.lumaStdDev <= t.maxLumaStdDev else {
            return .unclear
        }
        let saturation = maxC > 0 ? delta / maxC : 0
        guard saturation >= t.minSaturation, delta > 0 else { return .unclear }

        var hue: Double
        if maxC == s.r {
            hue = 60 * ((s.g - s.b) / delta)
        } else if maxC == s.g {
            hue = 60 * ((s.b - s.r) / delta + 2)
        } else {
            hue = 60 * ((s.r - s.g) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        guard t.hueRange.contains(hue) else { return .unclear }

        if maxC >= t.paleMinBrightness, hue >= t.paleMinHue { return .tooPale }
        if maxC <= t.darkMaxBrightness || hue <= t.darkMaxHue { return .maybeDark }
        return .nearTarget
    }
}

/// 连续多帧一致才算数；每种出声状态在一个步骤里只播报一次。
/// 读数在两档之间来回跳（灯光、蒸汽）时，文字照常更新，但不会反复出声。
struct ObservationStabilizer {
    struct Output: Equatable {
        /// 当前稳定状态，用于显示。nil 表示还没稳定下来。
        var display: CaramelReading?
        /// 本帧需要播报的状态，绝大多数时候为 nil。
        var announce: CaramelReading?
    }

    var requiredConsecutive: Int
    private(set) var stable: CaramelReading?
    private var candidate: CaramelReading?
    private var count = 0
    private var announced: Set<CaramelReading> = []

    init(requiredConsecutive: Int = 3) {
        self.requiredConsecutive = requiredConsecutive
    }

    mutating func ingest(_ reading: CaramelReading) -> Output {
        if reading == candidate {
            count += 1
        } else {
            candidate = reading
            count = 1
        }
        var announce: CaramelReading?
        if count >= requiredConsecutive, stable != reading {
            stable = reading
            if reading.spoken != nil, announced.insert(reading).inserted {
                announce = reading
            }
        }
        return Output(display: stable, announce: announce)
    }

    mutating func reset() {
        stable = nil
        candidate = nil
        count = 0
        announced = []
    }
}

enum FrameSampler {
    /// 从 BGRA 像素缓冲的中心方形选区按网格取样。只读内存，不落盘。
    static func stats(from buffer: CVPixelBuffer, roiFraction: Double = 0.4, grid: Int = 40) -> FrameStats? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let side = Int(Double(min(width, height)) * roiFraction)
        guard side >= grid, grid > 1 else { return nil }
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumL = 0.0, sumL2 = 0.0
        var glare = 0
        let n = grid * grid
        for gy in 0..<grid {
            let y = originY + gy * (side - 1) / (grid - 1)
            for gx in 0..<grid {
                let x = originX + gx * (side - 1) / (grid - 1)
                let p = pixels + y * bytesPerRow + x * 4
                let b = Double(p[0]) / 255, g = Double(p[1]) / 255, r = Double(p[2]) / 255
                let luma = 0.299 * r + 0.587 * g + 0.114 * b
                sumR += r; sumG += g; sumB += b
                sumL += luma; sumL2 += luma * luma
                if luma > 0.94 { glare += 1 }
            }
        }
        let count = Double(n)
        let meanL = sumL / count
        let variance = max(0, sumL2 / count - meanL * meanL)
        return FrameStats(
            r: sumR / count, g: sumG / count, b: sumB / count,
            glareFraction: Double(glare) / count,
            lumaStdDev: variance.squareRoot()
        )
    }
}
