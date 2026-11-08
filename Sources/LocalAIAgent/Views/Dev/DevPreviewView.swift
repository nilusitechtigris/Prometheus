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
    /// Zooms a page out until all of it fits, the way ⌘- would, instead of scrolling.
    var fitsPage = false
    /// Lets the Compare page reach the running page, to take its picture.
    var handle: DevPageHandle?

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
        let fitted = coordinator.parent.fitsPage
        coordinator.parent = self
        if coordinator.loadedID != loadID {
            coordinator.start()
        } else if fitted != fitsPage {
            coordinator.fit()
        }
        handle?.host = coordinator.host
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopFitting()
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
                parent.handle?.host = host
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
                guard let self else { return }
                if let sides = value as? [Int], sides.count == 2 { self.size = CGSize(width: sides[0], height: sides[1]) }
                self.fit()
            }
        }

        /// Zooming the page rather than the canvas, so a game's mouse positions still come out right.
        func fit() {
            guard let host, let box else { return }
            if let size, size.width > 0, size.height > 0 {
                let scale = min(box.bounds.width / size.width, box.bounds.height / size.height)
                host.webView.pageZoom = max(min(scale, 1.6), 0.4)
            } else if parent.fitsPage {
                // Sizes change many times while a pane opens, so this waits for them to settle.
                refit?.cancel()
                refit = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    await self?.fitPage(fromFullSize: true)
                }
                watchFit()
            } else {
                stopFitting()
                if host.webView.pageZoom != 1 { host.webView.pageZoom = 1 }
            }
        }

        private var refit: Task<Void, Never>?
        private var watch: Task<Void, Never>?

        /// A page grows as it's used, so a fitted one is checked again every second and zoomed out further
        /// if it no longer fits. It isn't zoomed back in until the window changes, so it doesn't jump about.
        private func watchFit() {
            guard watch == nil else { return }
            watch = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.parent.fitsPage, self.size == nil, self.parent.handle?.isCapturing != true else { continue }
                    await self.fitPage(fromFullSize: false)
                }
            }
        }

        func stopFitting() {
            refit?.cancel()
            refit = nil
            watch?.cancel()
            watch = nil
        }

        /// Starts from full size when asked, then zooms out until the page's height fits the pane. A page
        /// relays itself out when its zoom changes, so it takes a few goes.
        private func fitPage(fromFullSize: Bool) async {
            guard let webView = host?.webView, parent.fitsPage, size == nil else { return }
            if fromFullSize, webView.pageZoom != 1 {
                webView.pageZoom = 1
                try? await Task.sleep(for: .milliseconds(120))
            }
            for _ in 0..<5 {
                guard let sides = try? await webView.evaluateJavaScript("[document.documentElement.scrollHeight, innerHeight]") as? [Double],
                      sides.count == 2, sides[0] > 0, sides[1] > 0, sides[0] > sides[1] + 2 else { return }
                let next = max(webView.pageZoom * sides[1] / sides[0] * 0.98, 0.25)
                guard next < webView.pageZoom - 0.005, parent.fitsPage else { return }
                webView.pageZoom = next
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
}

/// The page a preview is running, for whoever needs its picture.
@MainActor
final class DevPageHandle {
    weak var host: DevPageHost?
    /// Set while a picture is taken, so fitting leaves the zoom alone.
    private(set) var isCapturing = false

    /// The whole page, not just what shows, as WebKit draws it into a PDF, so it stays sharp at any size.
    /// A page zoomed out to fit lays itself out wider, so it's put back to full size for a moment first,
    /// to match the other side.
    func picture() async -> NSImage? {
        guard let webView = host?.webView else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let zoom = webView.pageZoom
        if zoom != 1 {
            webView.pageZoom = 1
            try? await Task.sleep(for: .milliseconds(250))
        }
        let data: Data? = await withCheckedContinuation { continuation in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                continuation.resume(returning: try? result.get())
            }
        }
        if zoom != 1, host?.webView === webView { webView.pageZoom = zoom }
        guard let data, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }
}
