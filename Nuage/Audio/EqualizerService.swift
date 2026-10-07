//
//  EqualizerService.swift
//  Nuage
//
//  Created on 04.10.2026.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import MediaToolbox
import os

// MARK: - Equalizer Band Model

public struct EqualizerBand: Identifiable, Equatable {
    public let id: Int
    public let frequency: Float
    public let label: String
    public var gain: Float // in dB, range: -12.0 ... +12.0
}

// MARK: - Equalizer Preset Model

public struct EqualizerPreset: Identifiable, Equatable, Hashable {
    public let id: String
    public let nameEn: String
    public let nameRu: String
    public let gains: [Float] // 10 values for 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    
    public var localizedName: String {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        return lang == "ru" ? nameRu : nameEn
    }
    
    public static let flat = EqualizerPreset(
        id: "flat",
        nameEn: "Flat",
        nameRu: "Выключен (Flat)",
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    )
    
    public static let bassBoost = EqualizerPreset(
        id: "bass_boost",
        nameEn: "Bass Boost",
        nameRu: "Усиление басов",
        gains: [6.5, 5.5, 4.0, 2.0, 0.5, 0, 0, 0, 0, 0]
    )
    
    public static let bassReducer = EqualizerPreset(
        id: "bass_reducer",
        nameEn: "Bass Reducer",
        nameRu: "Снижение басов",
        gains: [-6.0, -5.0, -3.5, -2.0, 0, 0, 0, 0, 0, 0]
    )
    
    public static let trebleBoost = EqualizerPreset(
        id: "treble_boost",
        nameEn: "Treble Boost",
        nameRu: "Усиление ВЧ",
        gains: [0, 0, 0, 0, 0, 1.0, 2.5, 4.5, 6.0, 6.5]
    )
    
    public static let electronic = EqualizerPreset(
        id: "electronic",
        nameEn: "Electronic / EDM",
        nameRu: "Электроника / EDM",
        gains: [5.0, 4.5, 1.5, 0, -1.5, 2.0, 1.0, 2.5, 4.5, 5.0]
    )
    
    public static let hiphop = EqualizerPreset(
        id: "hiphop",
        nameEn: "Hip-Hop",
        nameRu: "Хип-хоп",
        gains: [6.0, 5.5, 2.5, 1.0, -1.0, -0.5, 1.5, 2.0, 3.5, 4.0]
    )
    
    public static let rock = EqualizerPreset(
        id: "rock",
        nameEn: "Rock",
        nameRu: "Рок",
        gains: [5.0, 3.5, -1.0, -2.0, 0.5, 2.5, 4.0, 4.5, 5.0, 5.0]
    )
    
    public static let pop = EqualizerPreset(
        id: "pop",
        nameEn: "Pop",
        nameRu: "Поп",
        gains: [-1.5, 1.0, 3.0, 4.0, 3.5, 1.5, -0.5, -1.0, 2.0, 2.5]
    )
    
    public static let vocal = EqualizerPreset(
        id: "vocal",
        nameEn: "Vocal Boost",
        nameRu: "Вокал / Подкасты",
        gains: [-2.0, -2.0, -1.0, 1.5, 3.5, 4.0, 3.5, 2.0, 0.5, -1.0]
    )
    
    public static let acoustic = EqualizerPreset(
        id: "acoustic",
        nameEn: "Acoustic",
        nameRu: "Акустика",
        gains: [3.5, 3.0, 1.5, 1.0, 1.5, 2.0, 3.0, 3.5, 3.0, 2.0]
    )
    
    public static let rnb = EqualizerPreset(
        id: "rnb",
        nameEn: "R&B",
        nameRu: "R&B / Соул",
        gains: [4.0, 6.0, 4.0, 1.0, -1.5, -1.0, 1.5, 2.5, 3.5, 4.0]
    )
    
    public static let classical = EqualizerPreset(
        id: "classical",
        nameEn: "Classical",
        nameRu: "Классика",
        gains: [4.5, 3.5, 2.5, 2.0, -1.0, -1.0, 0, 2.0, 3.0, 3.5]
    )
    
    public static let allPresets: [EqualizerPreset] = [
        .flat, .bassBoost, .bassReducer, .trebleBoost, .electronic,
        .hiphop, .rock, .pop, .vocal, .acoustic, .rnb, .classical
    ]
}

// MARK: - Biquad Filter Engine (DSP)

enum BiquadType {
    case lowShelf
    case peaking
    case highShelf
}

final class BiquadBand {
    let frequency: Float
    let type: BiquadType
    let q: Float
    
    private var b0: Float = 1
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    
    private var x1: [Float] = [0, 0]
    private var x2: [Float] = [0, 0]
    private var y1: [Float] = [0, 0]
    private var y2: [Float] = [0, 0]
    
    init(frequency: Float, type: BiquadType, q: Float = 1.414) {
        self.frequency = frequency
        self.type = type
        self.q = q
    }
    
    func reset() {
        x1 = [0, 0]
        x2 = [0, 0]
        y1 = [0, 0]
        y2 = [0, 0]
    }
    
    func update(sampleRate: Float, gainDB: Float) {
        guard sampleRate > 0 else { return }
        
        if abs(gainDB) < 0.05 {
            b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0
            return
        }
        
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * Float.pi * min(frequency, sampleRate * 0.48) / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * q)
        
        var rawB0: Float = 1
        var rawB1: Float = 0
        var rawB2: Float = 0
        var rawA0: Float = 1
        var rawA1: Float = 0
        var rawA2: Float = 0
        
        switch type {
        case .peaking:
            rawB0 = 1.0 + alpha * A
            rawB1 = -2.0 * cosW0
            rawB2 = 1.0 - alpha * A
            rawA0 = 1.0 + alpha / A
            rawA1 = -2.0 * cosW0
            rawA2 = 1.0 - alpha / A
            
        case .lowShelf:
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            rawB0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha)
            rawB1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0)
            rawB2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha)
            rawA0 = (A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha
            rawA1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0)
            rawA2 = (A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha
            
        case .highShelf:
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            rawB0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha)
            rawB1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0)
            rawB2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha)
            rawA0 = (A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha
            rawA1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0)
            rawA2 = (A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha
        }
        
        let invA0 = 1.0 / rawA0
        b0 = rawB0 * invA0
        b1 = rawB1 * invA0
        b2 = rawB2 * invA0
        a1 = rawA1 * invA0
        a2 = rawA2 * invA0
    }
    
    @inline(__always)
    func process(_ x: Float, channel: Int) -> Float {
        let ch = channel < 2 ? channel : 0
        let y = b0 * x + b1 * x1[ch] + b2 * x2[ch] - a1 * y1[ch] - a2 * y2[ch]
        x2[ch] = x1[ch]
        x1[ch] = x
        y2[ch] = y1[ch]
        y1[ch] = y
        return y
    }
}

// MARK: - Thread-Safe Real-time Audio Processor

final class EqualizerAudioProcessor: @unchecked Sendable {
    private var sampleRate: Float = 44100
    private var isEnabled: Bool = false
    private var preampLinear: Float = 1.0
    private let bands: [BiquadBand]
    private var lock = os_unfair_lock_s()
    
    init() {
        bands = [
            BiquadBand(frequency: 32, type: .lowShelf, q: 0.707),
            BiquadBand(frequency: 64, type: .peaking, q: 1.414),
            BiquadBand(frequency: 125, type: .peaking, q: 1.414),
            BiquadBand(frequency: 250, type: .peaking, q: 1.414),
            BiquadBand(frequency: 500, type: .peaking, q: 1.414),
            BiquadBand(frequency: 1000, type: .peaking, q: 1.414),
            BiquadBand(frequency: 2000, type: .peaking, q: 1.414),
            BiquadBand(frequency: 4000, type: .peaking, q: 1.414),
            BiquadBand(frequency: 8000, type: .peaking, q: 1.414),
            BiquadBand(frequency: 16000, type: .highShelf, q: 0.707)
        ]
    }
    
    func setSampleRate(_ rate: Float) {
        os_unfair_lock_lock(&lock)
        self.sampleRate = rate > 0 ? rate : 44100
        for band in bands {
            band.reset()
        }
        os_unfair_lock_unlock(&lock)
    }
    
    func updateConfig(enabled: Bool, preampDB: Float, gains: [Float]) {
        os_unfair_lock_lock(&lock)
        self.isEnabled = enabled
        self.preampLinear = pow(10.0, preampDB / 20.0)
        let count = min(bands.count, gains.count)
        for i in 0..<count {
            bands[i].update(sampleRate: sampleRate, gainDB: gains[i])
        }
        os_unfair_lock_unlock(&lock)
    }
    
    func reset() {
        os_unfair_lock_lock(&lock)
        for band in bands {
            band.reset()
        }
        os_unfair_lock_unlock(&lock)
    }
    
    func processAudio(bufferList: UnsafeMutablePointer<AudioBufferList>, numberFrames: CMItemCount) {
        guard isEnabled else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let frameCount = Int(numberFrames)
        guard frameCount > 0 else { return }
        
        if buffers.count >= 2 {
            // Non-interleaved stereo
            for ch in 0..<2 {
                guard let data = buffers[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<frameCount {
                    var sample = data[frame] * preampLinear
                    for band in bands {
                        sample = band.process(sample, channel: ch)
                    }
                    // Soft clip to prevent harsh digital distortion
                    data[frame] = max(-1.0, min(1.0, sample))
                }
            }
        } else if buffers.count == 1 {
            // Interleaved stereo
            guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            for frame in 0..<frameCount {
                let leftIdx = frame * 2
                let rightIdx = leftIdx + 1
                
                var leftSample = data[leftIdx] * preampLinear
                for band in bands {
                    leftSample = band.process(leftSample, channel: 0)
                }
                data[leftIdx] = max(-1.0, min(1.0, leftSample))
                
                if rightIdx < frameCount * 2 {
                    var rightSample = data[rightIdx] * preampLinear
                    for band in bands {
                        rightSample = band.process(rightSample, channel: 1)
                    }
                    data[rightIdx] = max(-1.0, min(1.0, rightSample))
                }
            }
        }
    }
}

// MARK: - Equalizer Service

@MainActor
public final class EqualizerService: ObservableObject {
    public static let shared = EqualizerService()
    
    public static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let frequencyLabels: [String] = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    
    @AppStorage("equalizer_enabled") public var isEnabled: Bool = false {
        didSet { syncProcessor() }
    }
    
    @AppStorage("equalizer_preamp") public var preampGain: Double = 0.0 {
        didSet { syncProcessor() }
    }
    
    @AppStorage("equalizer_preset_id") public var selectedPresetID: String = "flat"
    
    @Published public var bandGains: [Float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] {
        didSet {
            saveGains()
            syncProcessor()
        }
    }
    
    @Published public var isShowingEqualizer: Bool = false
    
    nonisolated let processor = EqualizerAudioProcessor()
    
    private init() {
        loadGains()
        syncProcessor()
    }
    
    private func loadGains() {
        if let saved = UserDefaults.standard.array(forKey: "equalizer_band_gains") as? [Float], saved.count == 10 {
            bandGains = saved
        } else {
            bandGains = EqualizerPreset.flat.gains
        }
    }
    
    private func saveGains() {
        UserDefaults.standard.set(bandGains, forKey: "equalizer_band_gains")
    }
    
    private func syncProcessor() {
        processor.updateConfig(enabled: isEnabled, preampDB: Float(preampGain), gains: bandGains)
    }
    
    public func applyPreset(_ preset: EqualizerPreset) {
        selectedPresetID = preset.id
        bandGains = preset.gains
    }
    
    public func setBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < bandGains.count else { return }
        bandGains[index] = max(-12.0, min(12.0, gain))
        selectedPresetID = "custom"
    }
    
    public func resetToFlat() {
        applyPreset(.flat)
        preampGain = 0.0
    }
    
    // MARK: - Attach Tap to AVPlayerItem
    
    nonisolated public func attach(to item: AVPlayerItem) {
        let processor = self.processor
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(processor).toOpaque()),
            init: { tap, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { _ in },
            prepare: { tap, maxFrames, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let proc = Unmanaged<EqualizerAudioProcessor>.fromOpaque(storage).takeUnretainedValue()
                proc.setSampleRate(Float(processingFormat.pointee.mSampleRate))
            },
            unprepare: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let proc = Unmanaged<EqualizerAudioProcessor>.fromOpaque(storage).takeUnretainedValue()
                proc.reset()
            },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                guard status == noErr else { return }
                let storage = MTAudioProcessingTapGetStorage(tap)
                let proc = Unmanaged<EqualizerAudioProcessor>.fromOpaque(storage).takeUnretainedValue()
                proc.processAudio(bufferList: bufferListInOut, numberFrames: numberFramesOut.pointee)
            }
        )
        
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr, let tap = tap else { return }
        
        let inputParams = AVMutableAudioMixInputParameters()
        inputParams.audioTapProcessor = tap
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]
        item.audioMix = audioMix
    }
}

// MARK: - Equalizer UI View

public struct EqualizerView: View {
    @ObservedObject private var service = EqualizerService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header: Title, Preset Picker, On/Off Switch
            headerView
            
            // Frequency Response Curve Visualizer
            curveVisualizer
                .frame(height: 54)
                .padding(.horizontal, 8)
            
            // Sliders Section
            HStack(spacing: 8) {
                // Preamp Slider
                preampColumn
                
                Divider()
                    .frame(height: 140)
                    .padding(.horizontal, 4)
                
                // 10 Frequency Bands
                HStack(spacing: 6) {
                    ForEach(0..<service.bandGains.count, id: \.self) { idx in
                        bandColumn(index: idx)
                    }
                }
            }
            .padding(.horizontal, 6)
            
            // Footer: Reset button & Status
            footerView
        }
        .padding(18)
        .frame(width: 480)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(service.isEnabled ? Color(hex: 0xFF5500) : .secondary)
                
                Text(LocalizedStringKey("equalizer.title"))
                    .font(.system(size: 14, weight: .bold))
            }
            
            Spacer()
            
            // Preset Dropdown
            Menu {
                ForEach(EqualizerPreset.allPresets) { preset in
                    Button(action: { service.applyPreset(preset) }) {
                        HStack {
                            Text(preset.localizedName)
                            if service.selectedPresetID == preset.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if service.selectedPresetID == "custom" {
                    Divider()
                    Button("Пользовательский (Custom)") {}
                        .disabled(true)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPresetDisplayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Power Toggle
            Toggle("", isOn: $service.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)
        }
    }
    
    private var currentPresetDisplayName: String {
        if service.selectedPresetID == "custom" {
            let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            return lang == "ru" ? "Пользовательский" : "Custom"
        }
        if let preset = EqualizerPreset.allPresets.first(where: { $0.id == service.selectedPresetID }) {
            return preset.localizedName
        }
        return EqualizerPreset.flat.localizedName
    }
    
    // MARK: - Curve Visualizer
    
    private var curveVisualizer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = service.bandGains.count
            let points = (0..<count).map { i -> CGPoint in
                let x = w * (CGFloat(i) / CGFloat(max(1, count - 1)))
                let normGain = CGFloat(service.bandGains[i]) / 12.0 // -1.0 ... +1.0
                let y = (h / 2.0) - (normGain * (h * 0.42))
                return CGPoint(x: x, y: y)
            }
            
            ZStack {
                // Background zero line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2.0))
                    p.addLine(to: CGPoint(x: w, y: h / 2.0))
                }
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Filled curve gradient
                if service.isEnabled {
                    Path { p in
                        guard let first = points.first else { return }
                        p.move(to: CGPoint(x: 0, y: h / 2.0))
                        p.addLine(to: first)
                        for i in 1..<points.count {
                            let prev = points[i - 1]
                            let curr = points[i]
                            let mid = CGPoint(x: (prev.x + curr.x) / 2.0, y: (prev.y + curr.y) / 2.0)
                            p.addQuadCurve(to: mid, control: prev)
                            p.addQuadCurve(to: curr, control: mid)
                        }
                        p.addLine(to: CGPoint(x: w, y: h / 2.0))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFF5500).opacity(0.28), Color(hex: 0xFF5500).opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                
                // Curve line
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for i in 1..<points.count {
                        let prev = points[i - 1]
                        let curr = points[i]
                        let mid = CGPoint(x: (prev.x + curr.x) / 2.0, y: (prev.y + curr.y) / 2.0)
                        p.addQuadCurve(to: mid, control: prev)
                        p.addQuadCurve(to: curr, control: mid)
                    }
                }
                .stroke(
                    service.isEnabled ? Color(hex: 0xFF5500) : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
    
    // MARK: - Preamp Column
    
    private var preampColumn: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f", service.preampGain))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(service.isEnabled ? Color(hex: 0xFF5500) : .secondary)
                .frame(height: 14)
            
            VerticalEQSlider(value: Binding(
                get: { Float(service.preampGain) },
                set: { service.preampGain = Double($0) }
            ), isEnabled: service.isEnabled)
            .frame(height: 110)
            
            Text("Pre")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(width: 32)
    }
    
    // MARK: - Band Column
    
    private func bandColumn(index: Int) -> some View {
        let gain = service.bandGains[index]
        let label = EqualizerService.frequencyLabels[index]
        
        return VStack(spacing: 6) {
            Text(String(format: "%+.0f", gain))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(gain != 0 && service.isEnabled ? Color(hex: 0xFF5500) : .secondary.opacity(0.7))
                .frame(height: 14)
            
            VerticalEQSlider(value: Binding(
                get: { service.bandGains[index] },
                set: { service.setBandGain(index: index, gain: $0) }
            ), isEnabled: service.isEnabled)
            .frame(height: 110)
            
            Text(label)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Text(service.isEnabled ? "Эквалайзер активен" : "Эквалайзер выключен")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Сбросить в 0 dB") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    service.resetToFlat()
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

// MARK: - Vertical Slider

struct VerticalEQSlider: View {
    @Binding var value: Float // -12 ... +12
    var isEnabled: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let progress = CGFloat((value + 12.0) / 24.0) // 0 ... 1 (0 at -12, 1 at +12)
            let thumbY = h * (1.0 - progress) // top is +12, bottom is -12
            
            ZStack(alignment: .top) {
                // Slider Track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 3.5, height: h)
                
                // Zero Marker Notch (at 0 dB center)
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 9, height: 1)
                    .position(x: w / 2, y: h / 2)
                
                // Active Fill Track from center zero
                let zeroY = h / 2.0
                let fillHeight = abs(thumbY - zeroY)
                let fillY = min(thumbY, zeroY)
                
                if fillHeight > 1 && isEnabled {
                    Capsule()
                        .fill(Color(hex: 0xFF5500).opacity(0.8))
                        .frame(width: 3.5, height: fillHeight)
                        .position(x: w / 2, y: fillY + fillHeight / 2)
                }
                
                // Thumb Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: isHovered ? 13 : 11, height: isHovered ? 13 : 11)
                    .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(isEnabled ? Color(hex: 0xFF5500) : Color.gray, lineWidth: 1.5)
                    )
                    .position(x: w / 2, y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = max(0, min(h, gesture.location.y))
                        let pct = Float(1.0 - (clampedY / h))
                        let newGain = -12.0 + (pct * 24.0)
                        value = max(-12.0, min(12.0, newGain))
                    }
            )
            .onTapGesture(count: 2) {
                // Double tap resets band to 0 dB
                value = 0
            }
        }
    }
}
