import Foundation

/// Single-producer / single-consumer float ring.
/// Capacity must be a power of two. No allocation after init.
final class SPSCFloatRing: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let mask: Int
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0

    init(capacityPowerOfTwo: Int) {
        precondition(capacityPowerOfTwo > 0 && capacityPowerOfTwo.nonzeroBitCount == 1)
        capacity = capacityPowerOfTwo
        mask = capacityPowerOfTwo - 1
        storage = .allocate(capacity: capacityPowerOfTwo)
        storage.initialize(repeating: 0, count: capacityPowerOfTwo)
    }

    deinit { storage.deallocate() }

    @inline(__always)
    func write(_ src: UnsafePointer<Float>, count: Int) {
        var w = writeIndex
        let m = mask
        let buf = storage
        for i in 0..<count {
            buf[w & m] = src[i]
            w &+= 1
        }
        writeIndex = w
    }

    @inline(__always)
    func read(_ dst: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let available = writeIndex &- readIndex
        let n = min(count, max(available, 0))
        var r = readIndex
        let m = mask
        let buf = storage
        for i in 0..<n {
            dst[i] = buf[r & m]
            r &+= 1
        }
        if n < count {
            dst.advanced(by: n).update(repeating: 0, count: count - n)
        }
        readIndex = r
        return n
    }

    func reset() {
        writeIndex = 0
        readIndex = 0
        storage.update(repeating: 0, count: capacity)
    }
}
