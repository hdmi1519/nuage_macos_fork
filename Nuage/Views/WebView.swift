//
//  WebView.swift
//  Nuage
//
//  Created by Laurin Brandner on 24.01.21.
//

import SwiftUI
import AppKit
import WebKit
import Combine

typealias CookieHandler = ((HTTPCookie) -> ())

struct WebView: NSViewRepresentable {
    
    private var url: URL
    private var coordinator = WebViewCoordinator()
    
    init(url: URL) {
        self.url = url
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        return coordinator
    }
    
    func makeNSView(context: Self.Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = WKWebsiteDataStore.default()
        conf.defaultWebpagePreferences.allowsContentJavaScript = true
        
        if let datadome = UserDefaults.standard.string(forKey: "datadome_cookie"),
           let cookie = HTTPCookie(properties: [
               .domain: ".soundcloud.com",
               .path: "/",
               .name: "datadome",
               .value: datadome,
               .secure: "TRUE",
               .expires: Date(timeIntervalSinceNow: 365 * 24 * 3600)
           ]) {
            conf.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
        
        let view = WKWebView(frame: .zero, configuration: conf)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        
        var request = URLRequest(url: url)
        request.setValue("https://soundcloud.com", forHTTPHeaderField: "Referer")
        view.load(request)
        
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        
        coordinator.webView = view
        
        return view
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func cookie(name: String, handler: @escaping CookieHandler) -> WebView {
        coordinator.handlers.append((name, handler))
        return self
    }
    
}

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, ObservableObject {

    var handlers = [(String, CookieHandler)]()
    var webView: WKWebView? {
        didSet {
            webView?.publisher(for: \.url)
                .sink { _ in self.scanCookiesForAccessToken() }
                .store(in: &cancellables)
        }
    }
    private var cancellables = Set<AnyCancellable>()

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        scanCookiesForAccessToken()
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        view.navigationDelegate = self
        view.uiDelegate = self
        
        let size = NSSize(width: windowFeatures.width?.doubleValue ?? 500, height: windowFeatures.height?.doubleValue ?? 500)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.closable, .titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.center()
        
        return view
    }
    
    func webViewDidClose(_ webView: WKWebView) {
        webView.window?.close()
    }
    
    private func scanCookiesForAccessToken() {
        guard let webView = webView else { return }
        let store = webView.configuration.websiteDataStore
        
        store.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                if cookie.name == "datadome" && !cookie.value.isEmpty {
                    UserDefaults.standard.set(cookie.value, forKey: "datadome_cookie")
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                if cookie.name == "_soundcloud_session" && !cookie.value.isEmpty {
                    UserDefaults.standard.set(cookie.value, forKey: "soundcloud_session")
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                for (name, handler) in self.handlers {
                    if name == cookie.name {
                        handler(cookie)
                    }
                }
            }
        }
    }
    
}
