import Foundation
import Testing
@testable import TyKaoz

@Suite
struct MathMarkupTests {

    @Test
    func rendersIsotopeNotation() {
        #expect(MathMarkup.render("Le plutonium ($^{244}\\text{Pu}$) est lourd.")
            == "Le plutonium (²⁴⁴Pu) est lourd.")
    }

    @Test
    func rendersSubscriptsAndSymbols() {
        #expect(MathMarkup.convert("H_2O") == "H₂O")
        #expect(MathMarkup.convert("a \\times b \\to c") == "a × b → c")
        #expect(MathMarkup.convert("\\alpha + \\beta") == "α + β")
    }

    @Test
    func stripsTextAndFrac() {
        #expect(MathMarkup.convert("\\frac{1}{2}") == "1/2")
        #expect(MathMarkup.convert("\\text{masse}") == "masse")
    }

    @Test
    func handlesDisplayMathAndParenDelimiters() {
        #expect(MathMarkup.render("$$E = mc^2$$") == "E = mc²")
        #expect(MathMarkup.render("\\(x^{10}\\)") == "x¹⁰")
    }

    @Test
    func leavesCurrencyAlone() {
        // No LaTeX signal between the dollars → not math.
        #expect(MathMarkup.render("Ça coûte $5 ou $10 selon la taille.")
            == "Ça coûte $5 ou $10 selon la taille.")
    }

    @Test
    func leavesCodeUntouched() {
        let input = "Voici `$^{2}$` en LaTeX et\n```\n$^{2}$\n```\nfin."
        // Inside inline code and fenced blocks the source is preserved.
        #expect(MathMarkup.render(input) == input)
    }

    @Test
    func convertsMathButKeepsSurroundingCode() {
        let out = MathMarkup.render("Isotope $^{14}\\text{C}$ et `code $x$`.")
        #expect(out == "Isotope ¹⁴C et `code $x$`.")
    }

    @Test
    func noDollarsIsIdentity() {
        #expect(MathMarkup.render("Texte simple sans maths.") == "Texte simple sans maths.")
    }

    @Test
    func unknownCommandKeepsItsName() {
        // A command with no symbol mapping degrades to its bare name.
        #expect(MathMarkup.convert("\\foobar x") == "foobar x")
    }
}
