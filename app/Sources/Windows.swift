import AppKit
import SwiftUI
import WebKit

@MainActor
final class LoginWindowController: NSWindowController {
    private let webView = WKWebView(frame: .zero)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = webView
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ url: URL, title: String) {
        window?.title = title
        webView.load(URLRequest(url: url))
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class TrafficWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = TrafficView(model: model)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "UniVPN 隔离流量"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 560))
        window.minSize = NSSize(width: 680, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
