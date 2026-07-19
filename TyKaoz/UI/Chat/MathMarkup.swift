import Foundation
import TyKaozKit

/// Lightweight LaTeX-math → Unicode/plain-text converter, applied to
/// assistant text at display time only (the stored message keeps the raw
/// content). The markdown engine doesn't render math, so models like
/// Gemini leave `$^{244}\text{Pu}$` visible as source; this turns it into
/// `²⁴⁴Pu`. Not a real TeX engine — it covers the inline notation chat
/// models actually emit (isotopes, simple formulas, Greek, arrows), and
/// leaves everything else untouched.
enum MathMarkup {

    /// Converts math spans in `text`. Fenced code blocks and inline code
    /// are preserved verbatim — math inside code is code, not math.
    static func render(_ text: String) -> String {
        guard text.contains("$") || text.contains("\\(") || text.contains("\\[") else {
            return text
        }
        return mapOutsideCode(text) { segment in
            var s = segment
            // Display math first ($$…$$, \[…\]), then inline ($…$, \(…\)).
            s = replaceSpans(s, open: "$$", close: "$$")
            s = replaceSpans(s, open: "\\[", close: "\\]")
            s = replaceSpans(s, open: "\\(", close: "\\)")
            s = replaceInlineDollar(s)
            return s
        }
    }

    // MARK: - Code protection

    /// Runs `transform` on the parts of `text` that are outside fenced
    /// code blocks (```…```) and inline code (`…`), leaving code verbatim.
    private static func mapOutsideCode(_ text: String, _ transform: (String) -> String) -> String {
        var out = ""
        var i = text.startIndex
        var plainStart = i
        func flushPlain(upTo end: String.Index) {
            if plainStart < end { out += transform(String(text[plainStart..<end])) }
        }
        while i < text.endIndex {
            if text[i...].hasPrefix("```") {
                flushPlain(upTo: i)
                let afterOpen = text.index(i, offsetBy: 3)
                if let closeRange = text.range(of: "```", range: afterOpen..<text.endIndex) {
                    out += String(text[i..<closeRange.upperBound])
                    i = closeRange.upperBound
                } else {
                    out += String(text[i...]); i = text.endIndex
                }
                plainStart = i
            } else if text[i] == "`" {
                flushPlain(upTo: i)
                let afterOpen = text.index(after: i)
                if let closeIndex = text[afterOpen...].firstIndex(of: "`") {
                    let end = text.index(after: closeIndex)
                    out += String(text[i..<end])
                    i = end
                } else {
                    out += String(text[i...]); i = text.endIndex
                }
                plainStart = i
            } else {
                i = text.index(after: i)
            }
        }
        flushPlain(upTo: text.endIndex)
        return out
    }

    // MARK: - Span replacement

    private static func replaceSpans(_ s: String, open: String, close: String) -> String {
        var out = ""
        var rest = Substring(s)
        while let openRange = rest.range(of: open) {
            let afterOpen = openRange.upperBound
            guard let closeRange = rest.range(of: close, range: afterOpen..<rest.endIndex) else {
                break
            }
            out += rest[..<openRange.lowerBound]
            out += convert(String(rest[afterOpen..<closeRange.lowerBound]))
            rest = rest[closeRange.upperBound...]
        }
        out += rest
        return out
    }

    /// Inline `$…$`: only treated as math when the body carries a LaTeX
    /// signal (backslash, `^`, `_`, `{`), so currency like "$5" is spared.
    private static func replaceInlineDollar(_ s: String) -> String {
        var out = ""
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "$") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "$") else { break }
            let body = String(rest[afterOpen..<close])
            out += rest[..<open]
            if body.contains(where: { "\\^_{".contains($0) }) {
                out += convert(body)
            } else {
                out += "$\(body)$"   // not math — leave verbatim
            }
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out
    }

    // MARK: - Math body conversion

    /// Converts the inside of a math span to Unicode/plain text.
    /// Regexes are built from strings (not `/…/` literals) to avoid the
    /// parser mis-reading `\s*/` as a comment terminator.
    static func convert(_ math: String) -> String {
        var s = math

        // \text{…} / \mathrm{…} / \mathbf{…} / \mathit{…} → inner content.
        s = s.replacing(reTextCmd) { m in cap(m, 1) }
        // \frac{a}{b} → a/b.
        s = s.replacing(reFrac) { m in "\(cap(m, 1))/\(cap(m, 2))" }
        // \left( \right) delimiters → bare.
        s = s.replacing(reLeft, with: "").replacing(reRight, with: "")
        // Named commands → symbols (unknown: keep the name).
        s = s.replacing(reNamed) { m in let n = cap(m, 1); return symbols[n] ?? n }
        // Superscripts / subscripts, braced then single-char.
        s = s.replacing(reSupBrace) { m in mapScript(cap(m, 1), superscript: true) }
        s = s.replacing(reSubBrace) { m in mapScript(cap(m, 1), superscript: false) }
        s = s.replacing(reSupChar) { m in mapScript(cap(m, 1), superscript: true) }
        s = s.replacing(reSubChar) { m in mapScript(cap(m, 1), superscript: false) }
        // Drop remaining braces and stray backslashes.
        s = s.replacing(reBraces, with: "").replacing(reBackslash, with: "")
        return s
    }

    private static func cap(_ match: Regex<AnyRegexOutput>.Match, _ index: Int) -> String {
        match.output[index].substring.map(String.init) ?? ""
    }

    private static let reTextCmd = try! Regex("\\\\(?:text|mathrm|mathbf|mathit|operatorname)\\{([^{}]*)\\}")
    private static let reFrac = try! Regex("\\\\frac\\{([^{}]*)\\}\\{([^{}]*)\\}")
    private static let reLeft = try! Regex("\\\\left\\s*")
    private static let reRight = try! Regex("\\\\right\\s*")
    private static let reNamed = try! Regex("\\\\([A-Za-z]+)")
    private static let reSupBrace = try! Regex("\\^\\{([^{}]*)\\}")
    private static let reSubBrace = try! Regex("_\\{([^{}]*)\\}")
    private static let reSupChar = try! Regex("\\^(.)")
    private static let reSubChar = try! Regex("_(.)")
    private static let reBraces = try! Regex("[{}]")
    private static let reBackslash = try! Regex("\\\\")

    /// Maps a run of characters to their super/subscript Unicode forms.
    /// Characters without a mapping are kept as-is.
    private static func mapScript(_ run: String, superscript: Bool) -> String {
        let table = superscript ? superscripts : subscripts
        return String(run.map { table[$0] ?? $0 })
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ"
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "h": "ₕ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "p": "ₚ",
        "s": "ₛ", "t": "ₜ"
    ]

    private static let symbols: [String: String] = [
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓",
        "approx": "≈", "neq": "≠", "leq": "≤", "geq": "≥", "ll": "≪", "gg": "≫",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "leftrightarrow": "↔", "infty": "∞", "propto": "∝",
        "sim": "∼", "equiv": "≡", "in": "∈", "notin": "∉", "subset": "⊂",
        "partial": "∂", "nabla": "∇", "sqrt": "√", "sum": "∑", "prod": "∏",
        "int": "∫", "circ": "°", "degree": "°", "ldots": "…", "dots": "…",
        "cdots": "⋯", "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
        "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "µ",
        "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ",
        "tau": "τ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ",
        "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ",
        "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ",
        "Psi": "Ψ", "Omega": "Ω", "quad": " ", "qquad": "  ", ",": " "
    ]
}
