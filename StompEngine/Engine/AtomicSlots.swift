import Foundation

/// Single-word parameter slot. Aligned 32/64-bit stores are atomic on ARM.
/// Used so the UI thread can publish knobs without taking a lock the audio thread would hit.
final class AtomicFloat: @unchecked Sendable {
    private let ptr: UnsafeMutablePointer<Float>

    init(_ value: Float) {
        ptr = .allocate(capacity: 1)
        ptr.initialize(to: value)
    }

    deinit { ptr.deallocate() }

    @inline(__always) func load() -> Float { ptr.pointee }
    @inline(__always) func store(_ value: Float) { ptr.pointee = value }
}

final class AtomicInt: @unchecked Sendable {
    private let ptr: UnsafeMutablePointer<Int>

    init(_ value: Int) {
        ptr = .allocate(capacity: 1)
        ptr.initialize(to: value)
    }

    deinit { ptr.deallocate() }

    @inline(__always) func load() -> Int { ptr.pointee }
    @inline(__always) func store(_ value: Int) { ptr.pointee = value }
}

final class AtomicBool: @unchecked Sendable {
    private let ptr: UnsafeMutablePointer<UInt8>

    init(_ value: Bool) {
        ptr = .allocate(capacity: 1)
        ptr.initialize(to: value ? 1 : 0)
    }

    deinit { ptr.deallocate() }

    @inline(__always) func load() -> Bool { ptr.pointee != 0 }
    @inline(__always) func store(_ value: Bool) { ptr.pointee = value ? 1 : 0 }
}
