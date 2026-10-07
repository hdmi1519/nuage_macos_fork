//
//  LoginView.swift
//  Nuage
//
//  Created by Laurin Brandner on 04.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import Combine

struct LoginView: View {
    
    private var onLogin: (String, Date?) -> ()
    
    @State private var loginMode: Int = 0 // 0 = Web, 1 = Token/Cookie
    @State private var tokenInput: String = UserDefaults.standard.string(forKey: "accessToken") ?? ""
    @State private var datadomeInput: String = UserDefaults.standard.string(forKey: "datadome_cookie") ?? ""
    @State private var sessionInput: String = UserDefaults.standard.string(forKey: "soundcloud_session") ?? ""
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Mode Switcher
            HStack(spacing: 12) {
                Picker("", selection: $loginMode) {
                    Text(LocalizedStringKey("login.embeddedBrowser")).tag(0)
                    Text(LocalizedStringKey("login.tokenInput")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                
                Spacer()
                
                Button(action: openInDefaultBrowser) {
                    HStack(spacing: 5) {
                        Image(systemName: "safari")
                        Text(LocalizedStringKey("login.openInBrowser"))
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if loginMode == 0 {
                // Mode 0: Web View
                ZStack(alignment: .bottom) {
                    WebView(url: URL(string: "https://soundcloud.com/signin")!)
                        .cookie(name: "oauth_token") { cookie in
                            onLogin(cookie.value, cookie.expiresDate)
                        }
                    
                    // Helpful overlay tip at bottom if user is stuck on captcha
                    HStack(spacing: 10) {
                        Image(systemName: "shield.slash.fill")
                            .foregroundColor(.orange)
                        Text(LocalizedStringKey("login.captchaNotice"))
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                        Spacer()
                        Button(LocalizedStringKey("login.enterTokenButton")) {
                            loginMode = 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0xFF5500))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .overlay(Divider(), alignment: .top)
                }
            } else {
                // Mode 1: Manual Token / Cookie Login
                manualLoginView
            }
        }
        .frame(minWidth: 950, minHeight: 650)
        .navigationTitle(LocalizedStringKey("login.title"))
    }
    
    private var manualLoginView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("login.quickLogin"))
                        .font(.system(size: 22, weight: .bold))
                    
                    Text(LocalizedStringKey("login.cloudflareExplanation"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
                
                // Token field
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("login.oauthTokenLabel"))
                        .font(.system(size: 13, weight: .semibold))
                    
                    TextField(LocalizedStringKey("login.oauthTokenPlaceholder"), text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }
                
                // DataDome Cookie field
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("login.datadomeLabel"))
                        .font(.system(size: 13, weight: .semibold))
                    
                    TextField(LocalizedStringKey("login.datadomePlaceholder"), text: $datadomeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                
                // SoundCloud Session Cookie field
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("login.sessionLabel"))
                        .font(.system(size: 13, weight: .semibold))
                    
                    TextField(LocalizedStringKey("login.sessionPlaceholder"), text: $sessionInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
                
                HStack(spacing: 12) {
                    Button(action: submitManualLogin) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text(LocalizedStringKey("login.submitButton"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0xFF5500))
                    
                    Button(action: openInDefaultBrowser) {
                        HStack(spacing: 6) {
                            Image(systemName: "safari")
                            Text(LocalizedStringKey("login.openSafariButton"))
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(.top, 4)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey("login.guideTitle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey("login.guideStep1"))
                        Text(LocalizedStringKey("login.guideStep2"))
                        Text(LocalizedStringKey("login.guideStep3"))
                        Text(LocalizedStringKey("login.guideStep4"))
                        Text(LocalizedStringKey("login.guideStep5"))
                    }
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .padding(32)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func submitManualLogin() {
        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            errorMessage = NSLocalizedString("login.enterTokenError", comment: "")
            return
        }
        
        let trimmedDataDome = datadomeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDataDome.isEmpty {
            UserDefaults.standard.set(trimmedDataDome, forKey: "datadome_cookie")
        }
        
        let trimmedSession = sessionInput.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if !trimmedSession.isEmpty {
            UserDefaults.standard.set(trimmedSession, forKey: "soundcloud_session")
        }
        
        errorMessage = nil
        onLogin(trimmedToken, nil)
    }
    
    private func openInDefaultBrowser() {
        if let url = URL(string: "https://soundcloud.com/signin") {
            NSWorkspace.shared.open(url)
        }
    }
    
    init(onLogin: @escaping (String, Date?) -> ()) {
        self.onLogin = onLogin
    }
}
