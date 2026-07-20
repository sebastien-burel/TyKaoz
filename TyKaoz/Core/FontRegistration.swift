import Foundation
import CoreText

/// Registers any .ttf/.otf font shipped in the app bundle with the system
/// font manager, so SwiftUI can resolve them via `Font.custom(family, size:)`.
/// Idempotent: calling more than once is safe (the system silently ignores
/// duplicate registrations).
enum FontRegistration {

    /// Scans the bundle's Resources root and registers every font file
    /// found. Designed to be called once from the app's init.
    static func registerBundledFonts() {
        guard let resourceURL = Bundle.main.resourceURL,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: resourceURL,
                  includingPropertiesForKeys: nil
              )
        else { return }

        let fontExtensions: Set<String> = ["ttf", "otf"]
        for url in urls where fontExtensions.contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        #if DEBUG
        let expected = ["Fraunces", "Inter Tight", "JetBrains Mono"]
        let available = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let resolved = expected.filter(available.contains)
        let missing = expected.filter { !available.contains($0) }
        print("[FontRegistration] resolved=\(resolved) missing=\(missing)")
        #endif
    }
}
