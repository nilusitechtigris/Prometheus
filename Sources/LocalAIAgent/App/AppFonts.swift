import CoreText
import Foundation

/// Registers the bundled Geist fonts for this process. Licensed under the SIL OFL (assets/fonts/OFL.txt).
enum AppFonts {
    static func register() {
        var folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        #if DEBUG
        // Debug builds run outside the app bundle, so use the copy in the repo.
        if folder.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("assets/fonts")
        }
        #endif
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}
