import AppKit
import SwiftUI

/// The AI-generated pictures the app shows, from assets/art. They're bundled with the app.
/// The lime pictures of the earlier look (window, home-hero, flame) are still in that folder, but
/// nothing shows them any more, so they are no longer loaded or bundled.
enum Art {
    private static let flameEmber = load(AppTheme.ember.flameArt)
    private static let flameRose = load(AppTheme.rose.flameArt)

    /// The glass flame for a theme: a cut-out on a clear background, so it can sit on any page.
    static func flame(for theme: AppTheme) -> NSImage? { theme == .ember ? flameEmber : flameRose }

    private static func load(_ name: String) -> NSImage? {
        var folder = Bundle.main.resourceURL?.appendingPathComponent("Art")
        #if DEBUG
        // Debug builds run outside the app bundle, so use the copy in the repo.
        if folder.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("assets/art")
        }
        #endif
        return folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("\(name).png")) }
    }
}
