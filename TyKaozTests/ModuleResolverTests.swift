import Foundation
import Testing
@testable import TyKaoz

@Suite
struct ModuleResolverTests {

    /// A temp libraries folder with `util.js` and `sub/deep.js`.
    private func makeLibs() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "tykaoz-mr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appending(path: "sub"), withIntermediateDirectories: true)
        try "export const a = 1;".write(
            to: dir.appending(path: "util.js"), atomically: true, encoding: .utf8)
        try "export const b = 2;".write(
            to: dir.appending(path: "sub/deep.js"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func entryResolvesToItselfAndServesSource() {
        let r = ModuleResolver(entrySource: "SRC", root: nil)
        #expect(r.find(specifier: "@agent", importer: nil) == "@agent")
        #expect(r.load(id: "@agent") == "SRC")
    }

    @Test func bareAndExtensionlessResolveFromRoot() throws {
        let dir = try makeLibs(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = ModuleResolver(entrySource: "", root: dir)
        let id = try #require(r.find(specifier: "util", importer: "@agent"))
        #expect(r.load(id: id)?.contains("a = 1") == true)
        #expect(r.find(specifier: "util.js", importer: "@agent") == id)
    }

    @Test func relativeResolvesFromImporterFolder() throws {
        let dir = try makeLibs(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = ModuleResolver(entrySource: "", root: dir)
        // A module in sub/ imports "./deep.js" — resolves next to the importer.
        let importer = dir.appending(path: "sub/other.js").path
        let id = try #require(r.find(specifier: "./deep.js", importer: importer))
        #expect(r.load(id: id)?.contains("b = 2") == true)
    }

    @Test func escapeOutsideRootIsRejected() throws {
        let dir = try makeLibs(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = ModuleResolver(entrySource: "", root: dir)
        #expect(r.find(specifier: "../secret", importer: "@agent") == nil)
        #expect(r.find(specifier: "/etc/hosts", importer: "@agent") == nil)
        #expect(r.load(id: "/etc/hosts") == nil)
    }

    @Test func missingModuleReturnsNil() throws {
        let dir = try makeLibs(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = ModuleResolver(entrySource: "", root: dir)
        #expect(r.find(specifier: "nope", importer: "@agent") == nil)
    }

    @Test func noRootDisablesLibraries() {
        let r = ModuleResolver(entrySource: "", root: nil)
        #expect(r.find(specifier: "util", importer: "@agent") == nil)
    }
}
