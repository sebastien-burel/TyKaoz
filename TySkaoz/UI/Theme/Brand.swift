import SwiftUI

enum Brand {
    enum Colors {
        static let ink       = Color(red: 0.055, green: 0.078, blue: 0.125)  // #0E1420
        static let inkSoft   = Color(red: 0.102, green: 0.122, blue: 0.180)  // #1A1F2E
        static let slate     = Color(red: 0.176, green: 0.231, blue: 0.322)  // #2D3B52
        static let tide      = Color(red: 0.310, green: 0.722, blue: 0.788)  // #4FB8C9
        static let tideBright = Color(red: 0.435, green: 0.831, blue: 0.898) // #6FD4E5
        static let foam      = Color(red: 0.722, green: 0.890, blue: 0.914)  // #B8E3E9
        static let paper     = Color(red: 0.969, green: 0.961, blue: 0.941)  // #F7F5F0
        static let ember     = Color(red: 0.910, green: 0.365, blue: 0.227)  // #E85D3A
    }

    enum Fonts {
        // Polices custom (Fraunces, Inter Tight, JetBrains Mono) à intégrer plus tard.
        // Placeholders via les designs sémantiques du système.
        static func title(_ size: CGFloat) -> Font { .system(size: size, design: .serif) }
        static func body(_ size: CGFloat) -> Font  { .system(size: size, design: .default) }
        static func mono(_ size: CGFloat) -> Font  { .system(size: size, design: .monospaced) }
    }

    static let accentGradient = LinearGradient(
        colors: [Colors.slate, Colors.tide],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
