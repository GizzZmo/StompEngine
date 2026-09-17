import AVFoundation
import Foundation
import os

struct EngineRouteInfo: Equatable {
    var inputName: String = "-"
    var outputName: String = "-"
    var sampleRate: Double = 0
    var bufferFrames: Int = 0
    var inputChannels: Int = 0
    var outputChannels: Int = 0
    var ioBufferMs: Double = 0
}

public final class LowLatencyGuitarEngine: ObservableObject {
    let dsp = GuitarDSP()

    private let engine = AVAudioEngine()
    private var sink: AVAudioSinkNode?
    private var source: AVAudioSourceNode?
    private let ring = SPSCFloatRing(capacityPowerOfTwo: 4096)
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchCount = 4096

    private let log = Logger(subsystem: "com.gizzzmo.StompEngine", category: "engine")
    private var routeObserver: NSObjectProtocol?
    private var configObserver: NSObjectProtocol?
    private var rebuildQueued = false

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var route = EngineRouteInfo()

    public init() {
        scratch = .allocate(capacity: scratchCount)
        scratch.initialize(repeating: 0, count: scratchCount)
    }

    deinit {
        scratch.deallocate()
        stop()
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }

    public func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: []
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(64.0 / 48_000.0)
        try session.setActive(true)

        refreshRouteInfo()
        log.info("session sr=\(self.route.sampleRate) buf=\(self.route.bufferFrames)")
    }

    public func setupGraph() throws {
        teardownGraph()
        dsp.reset()
        ring.reset()

        let input = engine.inputNode
        let output = engine.outputNode
        let hwIn = input.inputFormat(forBus: 0)
        let hwOut = output.outputFormat(forBus: 0)

        guard hwIn.sampleRate > 0, hwIn.channelCount > 0 else {
            throw NSError(
                domain: "StompEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No input format. Plug in the USB-C interface and try again."]
            )
        }

        let ringRef = ring
        let dspRef = dsp
        let scratchRef = scratch
        let scratchCap = scratchCount

        let sinkNode = AVAudioSinkNode { _, frameCount, abl -> OSStatus in
            let frames = Int(frameCount)
            if frames <= 0 || frames > scratchCap { return noErr }

            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
            guard buffers.count > 0, let mData = buffers[0].mData else { return noErr }

            let ch0 = mData.assumingMemoryBound(to: Float.self)
            let dest = scratchRef

            if dspRef.inputMode.load() == 1, buffers.count > 1, let rData = buffers[1].mData {
                let ch1 = rData.assumingMemoryBound(to: Float.self)
                for i in 0..<frames {
                    dest[i] = 0.5 * (ch0[i] + ch1[i])
                }
            } else {
                dest.update(from: ch0, count: frames)
            }

            dspRef.process(samples: dest, count: frames)
            ringRef.write(dest, count: frames)
            return noErr
        }

        let outCh = max(Int(hwOut.channelCount), 1)
        let sourceNode = AVAudioSourceNode { _, _, frameCount, abl -> OSStatus in
            let frames = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard buffers.count > 0, let mData = buffers[0].mData else { return noErr }

            let dst = mData.assumingMemoryBound(to: Float.self)
            _ = ringRef.read(dst, count: frames)

            if buffers.count > 1 {
                for ch in 1..<min(buffers.count, outCh + 4) {
                    if let p = buffers[ch].mData {
                        p.assumingMemoryBound(to: Float.self).update(from: dst, count: frames)
                    }
                }
            }
            return noErr
        }

        engine.attach(sinkNode)
        engine.attach(sourceNode)
        engine.connect(input, to: sinkNode, format: hwIn)

        let srcRate = hwOut.sampleRate > 0 ? hwOut.sampleRate : hwIn.sampleRate
        guard let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: srcRate,
            channels: AVAudioChannelCount(outCh),
            interleaved: false
        ) else {
            throw NSError(
                domain: "StompEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not build source format"]
            )
        }

        engine.connect(sourceNode, to: engine.mainMixerNode, format: srcFormat)
        engine.connect(engine.mainMixerNode, to: output, format: nil)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()

        sink = sinkNode
        source = sourceNode
        refreshRouteInfo()
        installObservers()
    }

    private func teardownGraph() {
        if engine.isRunning { engine.stop() }
        if let s = sink { engine.detach(s) }
        if let s = source { engine.detach(s) }
        sink = nil
        source = nil
    }

    private func installObservers() {
        let nc = NotificationCenter.default
        if routeObserver == nil {
            routeObserver = nc.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRebuild()
            }
        }
        if configObserver == nil {
            configObserver = nc.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRebuild()
            }
        }
    }

    private func scheduleRebuild() {
        guard isRunning, !rebuildQueued else {
            refreshRouteInfo()
            return
        }
        rebuildQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.rebuildQueued = false
            self.rebuildIfRunning()
        }
    }

    private func rebuildIfRunning() {
        guard isRunning else { return }
        do {
            try configureAudioSession()
            try setupGraph()
            try engine.start()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isRunning = false
            log.error("rebuild failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func report(_ message: String) {
        lastError = message
    }

    public func start() throws {
        guard !isRunning else { return }
        do {
            try configureAudioSession()
            try setupGraph()
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isRunning = false
            throw error
        }
    }

    public func stop() {
        teardownGraph()
        isRunning = false
    }

    public func setDelayMilliseconds(_ ms: Float) {
        let sr = max(route.sampleRate, 44_100)
        let n = Int((Double(ms) / 1000.0) * sr)
        dsp.delaySamples.store(max(n, 1))
    }

    func refreshRouteInfo() {
        let session = AVAudioSession.sharedInstance()
        let ins = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        let outs = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        let sr = session.sampleRate
        let frames = Int((session.ioBufferDuration * sr).rounded())
        let inFmt = engine.inputNode.inputFormat(forBus: 0)
        let outFmt = engine.outputNode.outputFormat(forBus: 0)

        route = EngineRouteInfo(
            inputName: ins.isEmpty ? "-" : ins,
            outputName: outs.isEmpty ? "-" : outs,
            sampleRate: sr,
            bufferFrames: frames,
            inputChannels: Int(inFmt.channelCount),
            outputChannels: Int(outFmt.channelCount),
            ioBufferMs: session.ioBufferDuration * 1000.0
        )
    }
}
