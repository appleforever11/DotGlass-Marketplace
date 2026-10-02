import AppKit
import SwiftUI
import WebKit

extension DotConnection: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if DotURLPolicy.allowsNavigation(url) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        ready = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        if let targetConversation, webView.url?.absoluteString != targetConversation {
            self.targetConversation = nil
            notice = "ChatGPT opened a different page. Check access to the selected Dot."
            showConnection = true
        }
        if DotURLPolicy.conversation(webView.url?.absoluteString) == nil { showConnection = true }
        webView.evaluateJavaScript(DotPageAdapter.source, completionHandler: nil)
        webView.evaluateJavaScript("window.__dotGlass?.refresh();", completionHandler: nil)
        openSignInIfNeeded()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; ready = false; typing = false; mediaPlaying = false
        notice = "ChatGPT couldn’t load. Check your connection, then reconnect."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false; ready = false; typing = false; mediaPlaying = false
        notice = "The connection paused. Reconnect to continue; your draft is still here."
        stopAudio()
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, DotURLPolicy.allowsNavigation(url) else { return nil }
        // Same-view auth matches the previously verified Dotty login flow.
        webView.load(navigationAction.request)
        return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard voiceStarting, frame.isMainFrame, origin.protocol == "https", origin.host == "chatgpt.com", type == .microphone,
              Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            notice = "This host cannot start a voice call. Open the conversation in your browser for calls."
            decisionHandler(.deny); return
        }
        decisionHandler(.prompt)
    }
}

struct DotWebSession: NSViewRepresentable {
    @Bindable var connection: DotConnection
    func makeNSView(context: Context) -> WKWebView { connection.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
