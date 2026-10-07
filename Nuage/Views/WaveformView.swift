//
//  WaveformView.swift
//  Nuage
//
//  Created by Laurin Brandner on 14.01.21.
//

import SwiftUI
import Combine
import SoundCloud

private let spacing: CGFloat = 3
private let barWidth: CGFloat = 3
private let emptyWaveform = Waveform(samples: Array(repeating: 2, count: 100))

struct WaveformView: View {
    
    var url: URL?
    @State private var waveform = emptyWaveform
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width)
            let numberOfBars = floor(CGFloat(availableWidth + spacing) / CGFloat(spacing + barWidth))
            let barCount = max(0, Int(numberOfBars))
            let samplesPerBar = barCount > 0 ? floor(CGFloat(waveform.samples.count) / CGFloat(barCount)) : 0
            let bars = barCount > 0 ? Array(0..<barCount)
                .map { bar -> CGFloat in
                    guard samplesPerBar > 0 else { return 0 }
                    let idx = CGFloat(bar) * samplesPerBar
                    let sample = interpolate(from: idx, to: idx + samplesPerBar) / CGFloat(max(1, waveform.maxHeight))
                    return CGFloat(pow(sample, 3))
                } : []
            let shouldScale = (self.waveform != emptyWaveform)
            let maxBar = bars.max() ?? 1.0
            
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    let height = shouldScale ? (bar / maxBar) * geometry.size.height : bar
                    
                    Rectangle()
                        .frame(width: barWidth, height: max(0, height))
                        .cornerRadius(barWidth/2)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .animation(.spring(), value: waveform)
        }
        .onAppear {
            guard let url = url else { return }
            SoundCloud.shared.get(.waveform(url))
                .replaceError(with: emptyWaveform)
                .receive(on: RunLoop.main)
                .sink { waveform in
                    withAnimation {
                        self.waveform = waveform
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    private func interpolate(from: CGFloat, to: CGFloat) -> CGFloat {
        guard !waveform.samples.isEmpty else { return 0 }
        let lhs = max(Int(round(from)), 0)
        let rhs = min(Int(round(to)), waveform.samples.count - 1)
        guard lhs <= rhs else { return 0 }
        let sum = waveform.samples[lhs...rhs].reduce(0, +)
        let cnt = rhs - lhs + 1

        return CGFloat(sum) / CGFloat(cnt)
    }
    
}

//struct WaveformView_Previews: PreviewProvider {
//    static var previews: some View {
//        let half = Array(1...50)
//        let samples = half.reversed() + half
//        let waveform = Waveform(samples: samples)
//        WaveformView(with: waveform)
//            .frame(width: 400, height: 100)
//            .foregroundColor(.accentColor)
//    }
//}
