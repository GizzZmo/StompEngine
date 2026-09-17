import SwiftUI
import AVFoundation

struct GuitarPedalView: View {
    @StateObject private var engine = LowLatencyGuitarEngine()

    @State private var drive: Float = 4.0
    @State private var tone: Float = 0.35
    @State private var delayMs: Float = 300
    @State private var feedback: Float = 0.40
    @State private var mix: Float = 0.30
    @State private var outputGain: Float = 0.55
    @State private var inputGain: Float = 1.0
    @State private var bypassed = false
    @State private var downmix = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                header
                routePanel
                knobs
                controls
                if let err = engine.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onAppear { pushAllParams() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("STOMP ENGINE")
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(.orange)
            Text("USB-C  •  MEASUREMENT I/O")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.gray)
        }
    }

    private var routePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("IN", engine.route.inputName)
            row("OUT", engine.route.outputName)
            row(
                "I/O",
                String(
                    format: "%.0f Hz  •  %d frames  •  %.2f ms  •  %d→%d ch",
                    engine.route.sampleRate,
                    engine.route.bufferFrames,
                    engine.route.ioBufferMs,
                    engine.route.inputChannels,
                    engine.route.outputChannels
                )
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(engine.isRunning ? 0.7 : 0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
    }

    private var knobs: some View {
        VStack(spacing: 14) {
            slider("INPUT", $inputGain, 0.2...2.0) {
                engine.dsp.inputGain.store(inputGain)
            }
            slider("DRIVE", $drive, 1.0...15.0) {
                engine.dsp.drive.store(drive)
            }
            slider("TONE", $tone, 0.05...0.95) {
                engine.dsp.tone.store(tone)
            }
            slider("DELAY MS", $delayMs, 20...900) {
                engine.setDelayMilliseconds(delayMs)
            }
            slider("FDBK", $feedback, 0.0...0.92) {
                engine.dsp.delayFeedback.store(feedback)
            }
            slider("MIX", $mix, 0.0...1.0) {
                engine.dsp.delayMix.store(mix)
            }
            slider("LEVEL", $outputGain, 0.05...1.2) {
                engine.dsp.outputGain.store(outputGain)
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Float>, _ range: ClosedRange<Float>, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.gray)
                Spacer()
                Text(display(title, value.wrappedValue))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            Slider(value: value, in: range)
                .tint(.orange)
                .onChange(of: value.wrappedValue) { _ in onChange() }
        }
    }

    private func display(_ title: String, _ v: Float) -> String {
        if title.contains("MS") { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                bypassed.toggle()
                engine.dsp.bypassed.store(bypassed)
            } label: {
                Text(bypassed ? "BYPASS" : "EFFECT")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(bypassed ? .gray : .green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
            }

            Button {
                downmix.toggle()
                engine.dsp.inputMode.store(downmix ? 1 : 0)
            } label: {
                Text(downmix ? "L+R" : "CH0")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 64)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
            }

            Button(action: togglePower) {
                Circle()
                    .fill(engine.isRunning ? Color.red : Color.gray.opacity(0.5))
                    .frame(width: 74, height: 74)
                    .overlay(
                        Text("PWR")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: engine.isRunning ? .red.opacity(0.6) : .clear, radius: 10)
            }
        }
    }

    private func pushAllParams() {
        engine.dsp.inputGain.store(inputGain)
        engine.dsp.drive.store(drive)
        engine.dsp.tone.store(tone)
        engine.dsp.delayFeedback.store(feedback)
        engine.dsp.delayMix.store(mix)
        engine.dsp.outputGain.store(outputGain)
        engine.dsp.bypassed.store(bypassed)
        engine.dsp.inputMode.store(downmix ? 1 : 0)
        engine.setDelayMilliseconds(delayMs)
    }

    private func togglePower() {
        if engine.isRunning {
            engine.stop()
        } else {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard granted else {
                        engine.report("Microphone permission denied")
                        return
                    }
                    do {
                        try engine.start()
                        engine.refreshRouteInfo()
                        engine.setDelayMilliseconds(delayMs)
                    } catch {
                    }
                }
            }
        }
    }
}
