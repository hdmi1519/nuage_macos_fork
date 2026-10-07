//
//  VoiceControlHUDView.swift
//  Nuage
//

import SwiftUI

struct VoiceControlHUDView: View {
    
    @ObservedObject var voiceService = VoiceControlService.shared
    
    var body: some View {
        if voiceService.isShowingHUD, let text = voiceService.currentHUDText {
            HStack(spacing: 9) {
                Image(systemName: voiceService.currentHUDIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: 0xFF5500))
                
                Text(text)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
            .padding(.top, 14)
        }
    }
}
