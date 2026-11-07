import AppKit
import SwiftUI
import WebKit

/// The Preview pane: a page from the project, running in the window, with no network.
struct DevPreviewView: NSViewRepresentable {
    let project: DevProject
    let path: String
    /// Changes each time the page should load again.
    let loadID: UUID
    let onMessage: (DevPageHost.Message) -> Void
    let onCrash: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let box = PreviewBox()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        box.onResize = { [weak coordinator = context.coordinator] in coordinator?.fit() }
        context.coordinator.box = box
        context.coordinator.start()
        return box
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.loadedID != loadID { coordinator.start() }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.host?.close()
        coordinator.host = nil
    }

    private final class PreviewBox: NSView {
        var onResize: (() -> Void)?
        override func layout() {
            super.layout()
            subviews.first?.frame = bounds
            onResize?()
        }
    }

    @MainActor
    final class Coordinator {
        var parent: DevPreviewView
        weak var box: NSView?
        var host: DevPageHost?
        var loadedID: UUID?
        private var size: CGSize?

        init(_ parent: DevPreviewView) { self.parent = parent }

        /// Each load starts a new view, so nothing a page set up survives into the next one.
        func start() {
            loadedID = parent.loadID
            let parent = parent
            Task { [weak self] in
                guard let list = await DevWeb.blockList() else {
                    parent.onMessage(.init(kind: .error, text: "Preview can't start safely on this version of macOS, so the page wasn't opened."))
                    return
                }
                guard let self, let box = self.box, self.loadedID == parent.loadID else { return }
                self.host?.close()
                guard let host = DevPageHost(project: parent.project, blockList: list, probing: false) else { return }
                host.onMessage = { [weak self] in self?.parent.onMessage($0) }
                host.onCrashed = { [weak self] in self?.parent.onCrash() }
                host.onLoaded = { [weak self] in self?.loaded() }
                self.host = host
                self.size = nil
                host.webView.frame = box.bounds
                host.webView.autoresizingMask = [.width, .height]
                box.addSubview(host.webView)
                host.load(parent.path)
            }
        }

        private func loaded() {
            guard let host else { return }
            host.webView.window?.makeFirstResponder(host.webView)
            host.webView.evaluateJavaScript("(() => { const c = document.querySelector('canvas'); return c ? [c.width, c.height] : null; })()") { [weak self] value, _ in
                guard let self, let sides = value as? [Int], sides.count == 2 else { return }
                self.size = CGSize(width: sides[0], height: sides[1])
                self.fit()
            }
        }

        /// Zooming the page rather than the canvas, so a game's mouse positions still come out right.
        func fit() {
            guard let host, let size, size.width > 0, size.height > 0, let box else { return }
            let scale = min(box.bounds.width / size.width, box.bounds.height / size.height)
            host.webView.pageZoom = max(min(scale, 1.6), 0.4)
        }
    }
}
