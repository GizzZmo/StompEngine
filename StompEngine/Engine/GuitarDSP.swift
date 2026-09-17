import Foundation

final class GuitarDSP: @unchecked Sendable {
    let inputGain = AtomicFloat(1.0)
    let drive = AtomicFloat(4.0)
    let tone = AtomicFloat(0.35)
    let outputGain = AtomicFloat(0.55)
    let delayMix = AtomicFloat(0.30)
    let delayFeedback = AtomicFloat(0.40)
    let delaySamples = AtomicInt(14_400)
    let bypassed = AtomicBool(false)
    /// 0 = guitar jack (channel 0 only), 1 = L+R downmix
    let inputMode = AtomicInt(0)

    private let delayPtr: UnsafeMutablePointer<Float>
    private let delayMask: Int
    private let delayCap: Int
    private var writeIdx: Int = 0
    private var lpState: Float = 0

    init(maxDelayPowerOfTwo: Int = 65_536) {
        precondition(maxDelayPowerOfTwo.nonzeroBitCount == 1)
        delayCap = maxDelayPowerOfTwo
        delayMask = maxDelayPowerOfTwo - 1
        delayPtr = .allocate(capacity: maxDelayPowerOfTwo)
        delayPtr.initialize(repeating: 0, count: maxDelayPowerOfTwo)
    }

    deinit { delayPtr.deallocate() }

    var maxDelaySamples: Int { delayCap - 1 }

    func reset() {
        writeIdx = 0
        lpState = 0
        delayPtr.update(repeating: 0, count: delayCap)
    }

    /// In-place mono process. Real-time safe: no alloc, no lock, no Swift Array.
    @inline(__always)
    func process(samples: UnsafeMutablePointer<Float>, count: Int) {
        if bypassed.load() { return }

        let inG = inputGain.load()
        let drv = max(drive.load(), 0.1)
        let alpha = min(max(tone.load(), 0.01), 0.99)
        let outG = outputGain.load()
        let mix = min(max(delayMix.load(), 0), 1)
        let fb = min(max(delayFeedback.load(), 0), 0.95)
        var off = delaySamples.load()
        if off < 1 { off = 1 }
        if off > delayCap - 1 { off = delayCap - 1 }

        var lp = lpState
        var w = writeIdx
        let mask = delayMask
        let buf = delayPtr
        let inv3: Float = 1.0 / 3.0

        for i in 0..<count {
            let x = samples[i] * inG
            let d = x * drv
            let clipped: Float
            if d > 1 {
                clipped = 1
            } else if d < -1 {
                clipped = -1
            } else {
                clipped = d - (d * d * d) * inv3
            }

            lp += alpha * (clipped - lp)

            let delayed = buf[(w &- off) & mask]
            buf[w & mask] = lp + delayed * fb
            w &+= 1

            samples[i] = (lp * (1 - mix) + delayed * mix) * outG
        }

        lpState = lp
        writeIdx = w
    }
}
